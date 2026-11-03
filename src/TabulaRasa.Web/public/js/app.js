// NOTE:
//   Entry point of the web UI, loaded by index.html as ES module.
//   Holds the shared app context and switches between the views.

import { releaseSession, hasToken, SessionLostError } from './utils/api.js'
import { esc } from './utils/format.js'

import views from './views/_index.js'

const TOAST_MS = 4000

//
//   Chapters:
//     APP CONTEXT   Navigation, toast and the jobs the views share.
//     START         Release button and the first view.
//

// ===========================================================================
// =============================   APP CONTEXT   =============================
// ===========================================================================
//
//   app.go          Shows a view, a lost session always leads back to the start screen.
//   app.isCurrent   Lets polling loops stop once the user navigated away.
//   app.toast       Shows a short message at the bottom.
//   app.jobs        Running job per disk and type, so a tab resumes its progress.
//

const root = document.getElementById('app')
const releaseButton = document.getElementById('release')
const toastElement = document.getElementById('toast')

let navigationId = 0
let toastTimer = null

const app = {
    root,
    jobs: {},
    cache: {},

    async go(viewName, params = {}) {
        const currentId = ++navigationId
        releaseButton.hidden = viewName === 'start' || !hasToken()
        window.scrollTo(0, 0)

        try {
            await views[viewName]({ app, params, navId: currentId })
        } catch (exception) {
            if (exception instanceof SessionLostError) {
                app.toast(exception.message)
                return app.go('start')
            }
            console.error(exception)
            root.innerHTML = `<div class="notice error">${esc(exception.message)}</div>
                <button class="block" id="error-back">Back to the disks</button>`
            root.querySelector('#error-back').addEventListener('click', () => app.go('disks'))
        }
    },

    isCurrent(navId) {
        return navId === navigationId
    },

    toast(message) {
        toastElement.textContent = message
        toastElement.hidden = false
        clearTimeout(toastTimer)
        toastTimer = setTimeout(() => { toastElement.hidden = true }, TOAST_MS)
    },

    jobKey(diskName, type) {
        return `${diskName}:${type}`
    },
}

// ===========================================================================
// ================================   START   ================================
// ===========================================================================
//
//   1. Release   Gives the session back, so another device can take control.
//   2. First     The disks with a stored token, else the start screen.
//

// ---------------------------------------------------------------------------
// Release
//   Gives the session back, so another device can take control.
// ---------------------------------------------------------------------------

releaseButton.addEventListener('click', async () => {
    await releaseSession()
    app.toast('Session released.')
    await app.go('start')
})

// ---------------------------------------------------------------------------
// First
//   The disks with a stored token, else the start screen.
// ---------------------------------------------------------------------------

await app.go(hasToken() ? 'disks' : 'start')
