// NOTE:
//   API client of the web UI. Keeps the session token and sends it with every request.
//   A 423 answer means the session is gone, the app returns to the start screen.

const TOKEN_KEY = 'tabula-rasa-token'
const JOB_POLL_MS = 1000

// ===========================================================================
// =============================   API CLIENT   ==============================
// ===========================================================================
//
//   SessionLostError   Thrown on 423, the caller shows the start screen.
//   getToken           Reads the token from the session storage.
//   setToken           Stores or forgets the token.
//   request            One JSON request with the token, throws with the server's message.
//   claimSession       Claims the session, stores the token.
//   releaseSession     Releases the session, forgets the token.
//   hasToken           Whether this page holds a token.
//   runJob             Starts a job and polls it until it is no longer running.
//   pollJob            Polls a started job until it is no longer running.
//

export class SessionLostError extends Error {}

function getToken() {
    try {
        return sessionStorage.getItem(TOKEN_KEY)
    } catch {
        return null
    }
}

function setToken(token) {
    try {
        if (null == token) sessionStorage.removeItem(TOKEN_KEY)
        else sessionStorage.setItem(TOKEN_KEY, token)
    } catch {
        // Private mode without storage: the token lives as long as the page.
    }
    memoryToken = token
}

let memoryToken = getToken()

/**
 * Sends one JSON request with the session token.
 *
 * @param {string}  path            (Required) The API path, e.g. '/api/disks'.
 * @param {string}  [method='GET']  (Optional) The HTTP method.
 * @param {object}  [body]          (Optional) Sent as JSON.
 * @returns {Promise<object>} The parsed JSON answer.
 *
 * @example
 * const { disks } = await request({ path: '/api/disks' })
 */
export async function request({ path, method = 'GET', body }) {
    const headers = { 'Accept': 'application/json' }
    if (null != memoryToken) headers['X-Session-Token'] = memoryToken
    if (null != body) headers['Content-Type'] = 'application/json'

    const response = await fetch(path, { method, headers, body: null == body ? undefined : JSON.stringify(body) })
    const data = await response.json().catch(() => ({}))

    if (response.status === 423 && path !== '/api/session') {
        setToken(null)
        throw new SessionLostError(data.error ?? 'The session was lost.')
    }
    if (!response.ok && response.status !== 423) {
        throw new Error(data.error ?? `Request to ${path} failed with ${response.status}.`)
    }
    return data
}

/**
 * Claims the control session. Returns the server answer, isGranted says whether it worked.
 *
 * @param {boolean} [isTakeover=false]   (Optional) Takes the session over, only honoured for the kiosk.
 * @returns {Promise<{isGranted: boolean, ownerAddress: string, secondsLeft: number}>}
 */
export async function claimSession({ isTakeover = false } = {}) {
    const result = await request({ path: '/api/session', method: 'POST', body: { isTakeover } })
    if (result.isGranted) setToken(result.token)
    return result
}

export async function releaseSession() {
    await request({ path: '/api/session', method: 'DELETE' }).catch(() => null)
    setToken(null)
}

export function hasToken() {
    return null != memoryToken
}

/**
 * Starts a job and polls it until it is done, failed or cancelled.
 *
 * @param {object}   body                 (Required) { type, disk, partition?, serial? }
 * @param {function} [onProgress]         (Optional) Called with the job on every poll.
 * @param {object}   [control]            (Optional) Gets control.jobId, to cancel from outside.
 * @returns {Promise<object>} The finished job.
 *
 * @example
 * const job = await runJob({ body: { type: 'Overview', disk: 'sdb' } })
 */
export async function runJob({ body, onProgress = () => {}, control = {} }) {
    const { id } = await request({ path: '/api/jobs', method: 'POST', body })
    control.jobId = id
    return pollJob({ id, onProgress })
}

export async function pollJob({ id, onProgress = () => {} }) {
    while (true) {
        const job = await request({ path: `/api/jobs/${encodeURIComponent(id)}` })
        onProgress(job)
        if (job.status !== 'Running') return job
        await new Promise(resolve => setTimeout(resolve, JOB_POLL_MS))
    }
}
