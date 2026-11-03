// NOTE:
//   Wipe tab. Confirms the disk the way the server says (disk.Wipe.Confirmation):
//   > Serial   Type the serial from the label, the server compares it.
//   > Replug   Unplug the device and plug it in again, the device that comes back is wiped.

import { request, runJob, pollJob } from '../../utils/api.js'
import { esc, formatSize } from '../../utils/format.js'

const TAB_ID = 'wipe'
const REPLUG_POLL_MS = 1000

// ===========================================================================
// ==============================   WIPE TAB   ===============================
// ===========================================================================
//
//   renderPlan      Method, confirmation and the warning of the disk kind.
//   showJob         Polls the wipe job and shows the result.
//   renderSerial    Serial input and the wipe button.
//   runReplug       Steps of the replug, then the final button.
//   render          Plan plus the fitting confirmation.
//

function renderPlan(disk) {
    const wipe = disk.Wipe
    return `
        <div class="card danger">
            <h2>Wipe plan</h2>
            <p>Method: <strong>${esc(wipe.Method)}</strong></p>
            <p>Confirmation: <strong>${wipe.Confirmation === 'Serial' ? 'type the serial from the label' : 'unplug and plug in again'}</strong></p>
            ${null != wipe.Warning ? `<div class="notice">${esc(wipe.Warning)}</div>` : ''}
        </div>`
}

async function showJob({ app, el, navId, job: startedJob, id }) {
    el.innerHTML = '<div class="card"><span class="spinner"></span>Wiping ...</div>'
    const job = startedJob ?? await pollJob({ id })
    if (!app.isCurrent(navId)) return
    el.innerHTML = job.status === 'Done'
        ? `<div class="notice ok">Wiped ${esc(job.result?.Path)} with ${esc(job.result?.Method)}.</div>`
        : `<div class="notice error">${esc(job.error ?? job.status)}</div>`
}

function renderSerial(disk) {
    const token = disk.Serial || disk.Path
    return `
        <div class="card">
            <p>Type <strong class="mono">${esc(token)}</strong> to wipe this disk. Compare it with the label on the disk.</p>
            <input type="text" id="serial" autocomplete="off" autocapitalize="off" spellcheck="false" placeholder="${esc(disk.Serial ? 'Serial number' : 'Device path')}">
            <div style="margin-top:10px"><button class="danger block" id="wipe" disabled>Wipe ${esc(formatSize(disk.SizeBytes))} for good</button></div>
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
    const isSerial = disk.Wipe.Confirmation === 'Serial'
    el.innerHTML = renderPlan(disk) + (isSerial
        ? renderSerial(disk)
        : '<div class="card"><p>USB sticks and SD cards rarely carry a real serial. Unplug the device and plug it in again, that selects it for sure.</p><button class="danger block" id="replug">Start</button></div>') + '<div id="flow"></div>'

    const flow = el.querySelector('#flow')

    if (isSerial) {
        const input = el.querySelector('#serial')
        const button = el.querySelector('#wipe')
        input.addEventListener('input', () => { button.disabled = input.value.trim() === '' })
        button.addEventListener('click', async () => {
            button.disabled = true
            try {
                const job = await runJob({ body: { type: 'Wipe', disk: disk.Name, serial: input.value.trim() } })
                await showJob({ app, el: flow, navId, job })
            } catch (exception) {
                flow.innerHTML = `<div class="notice error">${esc(exception.message)}</div>`
                button.disabled = false
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

export default { id: TAB_ID, label: '🧹 Wipe', isDanger: true, render }
