// NOTE:
//   Wipe tab. Confirms the disk the way the server says (disk.Wipe.Confirmation):
//   > Serial   Model, size and serial are shown, a checkbox unlocks the wipe button. The shown
//              serial goes along, the server refuses the wipe when the disk under that name changed.
//   > Replug   Unplug the device and plug it in again, the device that comes back is wiped.

//
//   Chapters:
//     WIPE TAB   Wipe plan, serial or replug, progress and check.
//

import { request, runJob, pollJob } from '../../utils/api.js'
import { esc, formatSize } from '../../utils/format.js'

const TAB_ID = 'wipe'
const REPLUG_POLL_MS = 1000

// ===========================================================================
// ==============================   WIPE TAB   ===============================
// ===========================================================================
//
//   renderPlan      Method, confirmation and the warning of the disk kind.
//   showJob         Starts or follows the wipe job with progress, shows the check.
//   renderSerial    The disk with its serial, the checkbox and the wipe button.
//   runReplug       Steps of the replug, then the final button.
//   render          Plan plus the fitting confirmation, or the progress of a wipe that still runs.
//

function renderPlan(disk) {
    const wipe = disk.Wipe
    return `
        <div class="card danger">
            <h2>Wipe plan</h2>
            <p>Method: <strong>${esc(wipe.Method)}</strong></p>
            <p>Confirmation: <strong>${wipe.Confirmation === 'Serial' ? 'check model, size and serial' : 'unplug and plug in again'}</strong></p>
            ${null != wipe.Warning ? `<div class="notice">${esc(wipe.Warning)}</div>` : ''}
        </div>`
}

// Starts the wipe job (body) or follows a started one (id), with progress and the check at the end.
async function showJob({ app, el, navId, body, id }) {
    const onProgress = job => {
        if (!app.isCurrent(navId) || job.status !== 'Running') return
        el.innerHTML = `
            <div class="card">
                <p><span class="spinner"></span>Wiping ... <strong>${esc(job.percent)} %</strong></p>
                <div class="progress"><div style="width:${Number(job.percent)}%"></div></div>
                <p class="muted small">Do not unplug the disk. A secure erase reports no progress, the bar follows the drive's own estimate.</p>
            </div>`
    }

    el.innerHTML = '<div class="card"><span class="spinner"></span>Starting the wipe ...</div>'
    const job = null != body
        ? await runJob({ body, onProgress })
        : await pollJob({ id, onProgress })
    if (!app.isCurrent(navId)) return

    if (job.status !== 'Done') {
        el.innerHTML = `<div class="notice error">Wipe failed: ${esc(job.error ?? job.status)}</div>`
        return
    }
    const result = job.result
    const check = result.IsAllZero
        ? 'all sampled blocks read zero'
        : `${result.NonZeroCount} of ${result.SampleCount} sampled blocks are not zero (normal after a crypto erase)`
    el.innerHTML = `
        <div class="notice ok">Wiped ${esc(result.Path)} with ${esc(result.Detail)} in ${esc(result.Seconds)} s.</div>
        <p class="muted">Check: ${esc(check)}.</p>`
}

function renderSerial(disk) {
    return `
        <div class="card">
            <table>
                <tr><th>Model</th><td>${esc(disk.Model || disk.Name)}</td></tr>
                <tr><th>Size</th><td>${esc(formatSize(disk.SizeBytes))}</td></tr>
                <tr><th>Serial</th><td class="mono"><strong>${esc(disk.Serial || 'no serial')}</strong></td></tr>
                <tr><th>Device</th><td class="mono">${esc(disk.Path)}</td></tr>
            </table>
            <label class="check"><input type="checkbox" id="confirm-disk"> This is the disk I want to wipe, everything on it is lost.</label>
            <button class="danger block" id="wipe" disabled>Wipe ${esc(formatSize(disk.SizeBytes))} for good</button>
        </div>`
}

async function runReplug({ app, disk, el, navId }) {
    const steps = phase => {
        const order = ['Unplug', 'Plug', 'Ready']
        const index = order.indexOf(phase)
        const step = (name, text) => {
            const position = order.indexOf(name)
            const state = position < index ? 'done' : position === index ? 'active' : ''
            return `<li class="${state}">${position < index ? '✅' : position === index ? '👉' : '⏳'} ${text}</li>`
        }
        return `<ol class="steps">
            ${step('Unplug', `Unplug <strong>${esc(disk.Model || disk.Name)}</strong>`)}
            ${step('Plug', 'Plug it in again')}
            ${step('Ready', 'Confirm the wipe')}
        </ol>`
    }

    await request({ path: '/api/replug', method: 'POST', body: { disk: disk.Name } })

    while (app.isCurrent(navId)) {
        const state = await request({ path: '/api/replug' })
        if (state.phase === 'Failed') {
            el.innerHTML = `<div class="notice error">${esc(state.reason)} Nothing was wiped.</div>`
            return
        }
        if (state.phase === 'Ready') {
            const added = state.added
            el.innerHTML = `
                <div class="card">
                    ${steps('Ready')}
                    <p>Found <strong>${esc(added.Model || added.Name)}</strong> (${esc(added.Path)}, ${esc(formatSize(added.SizeBytes))}).</p>
                    <button class="danger block" id="confirm">Wipe it for good</button>
                    <div style="margin-top:8px"><button class="block" id="abort">Cancel</button></div>
                </div>`
            el.querySelector('#abort').addEventListener('click', async () => {
                await request({ path: '/api/replug', method: 'DELETE' })
                void app.go('disks')
            })
            el.querySelector('#confirm').addEventListener('click', async () => {
                const { id } = await request({ path: '/api/replug/confirm', method: 'POST' })
                await showJob({ app, el, navId, id })
            })
            return
        }
        el.innerHTML = `<div class="card">${steps(state.phase)}<p class="muted small"><span class="spinner"></span>Waiting ...</p></div>`
        await new Promise(resolve => setTimeout(resolve, REPLUG_POLL_MS))
    }

    // Left the tab during the replug: nothing may wait for a device in the background.
    await request({ path: '/api/replug', method: 'DELETE' }).catch(() => null)
}

async function render({ app, disk, el, navId }) {
    // A wipe that still runs (started before a reload or on another device) is followed, not offered again.
    const runningId = app.jobs[app.jobKey(disk.Name, 'Wipe')]
    if (null != runningId) {
        el.innerHTML = renderPlan(disk) + '<div id="flow"></div>'
        await showJob({ app, el: el.querySelector('#flow'), navId, id: runningId })
        delete app.jobs[app.jobKey(disk.Name, 'Wipe')]
        return
    }

    const isSerial = disk.Wipe.Confirmation === 'Serial'
    el.innerHTML = renderPlan(disk) + (isSerial
        ? renderSerial(disk)
        : '<div class="card"><p>USB sticks and SD cards rarely carry a real serial. Unplug the device and plug it in again, that selects it for sure.</p><button class="danger block" id="replug">Start</button></div>') + '<div id="flow"></div>'

    const flow = el.querySelector('#flow')

    if (isSerial) {
        const checkbox = el.querySelector('#confirm-disk')
        const button = el.querySelector('#wipe')
        checkbox.addEventListener('change', () => { button.disabled = !checkbox.checked })
        button.addEventListener('click', async () => {
            button.disabled = true
            checkbox.disabled = true
            try {
                // The shown serial (or the path without one) lets the server spot a swapped disk.
                await showJob({ app, el: flow, navId, body: { type: 'Wipe', disk: disk.Name, serial: disk.Serial || disk.Path } })
            } catch (exception) {
                flow.innerHTML = `<div class="notice error">${esc(exception.message)}</div>`
                button.disabled = false
                checkbox.disabled = false
            }
        })
        return
    }

    el.querySelector('#replug').addEventListener('click', event => {
        event.target.hidden = true
        void runReplug({ app, disk, el: flow, navId }).catch(exception => {
            flow.innerHTML = `<div class="notice error">${esc(exception.message)}</div>`
        })
    })
}

export default { id: TAB_ID, label: '🧹 Wipe', isDanger: true, jobType: 'Wipe', render }
