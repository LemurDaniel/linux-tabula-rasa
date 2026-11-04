// NOTE:
//   Deep scan tab (stage 3): counts file headers over the whole disk, also after a quick format.
//   The scan runs on the server, leaving the tab does not stop it, coming back resumes the progress.

//
//   Chapters:
//     DEEP SCAN TAB   Starts or resumes the scan, progress and result.
//

import { request, runJob, pollJob } from '../../utils/api.js'
import { esc, formatSize, renderBars } from '../../utils/format.js'

const TAB_ID = 'deepscan'

// ===========================================================================
// ============================   DEEP SCAN TAB   ============================
// ===========================================================================
//
//   renderProgress   The progress card, rendered once: percent, bar and hits are updated in place.
//   render           Start button, then progress until done.
//

function renderProgress() {
    return `
        <div class="card">
            <p><span class="spinner"></span><span id="scan-state">Scanning ...</span> <strong id="scan-percent">0 %</strong></p>
            <div class="progress"><div id="scan-bar" style="width:0%"></div></div>
            <div id="scan-hits"></div>
            <div style="margin-top:12px"><button class="block" id="cancel">Stop scan</button></div>
        </div>`
}

async function render({ app, disk, el, navId }) {
    const key = app.jobKey(disk.Name, 'DeepScan')

    const run = async jobId => {
        // Rendered once and updated in place: a re-render every poll would replace the stop
        // button between press and release, and the click would get lost.
        let isRendered = false
        const onProgress = job => {
            if (!app.isCurrent(navId)) return
            if (!isRendered) {
                el.innerHTML = renderProgress()
                el.querySelector('#cancel').addEventListener('click', event => {
                    event.currentTarget.disabled = true
                    el.querySelector('#scan-state').textContent = 'Stopping ...'
                    void request({ path: `/api/jobs/${encodeURIComponent(app.jobs[key])}`, method: 'DELETE' })
                        .catch(exception => app.toast(exception.message))
                })
                isRendered = true
            }
            el.querySelector('#scan-percent').textContent = `${Number(job.percent)} %`
            el.querySelector('#scan-bar').style.width = `${Number(job.percent)}%`
            el.querySelector('#scan-hits').innerHTML = renderBars(job.hits)
        }
        const job = null != jobId
            ? await pollJob({ id: jobId, onProgress })
            : await runJob({ body: { type: 'DeepScan', disk: disk.Name }, onProgress, control: { set jobId(id) { app.jobs[key] = id } } })
        delete app.jobs[key]

        if (!app.isCurrent(navId)) return
        if (job.status === 'Failed') {
            el.innerHTML = `<div class="notice error">${esc(job.error)}</div>`
            return
        }
        const scanned = formatSize(job.result?.BytesScanned ?? 0)
        el.innerHTML = `
            <div class="card">
                <div class="notice ${job.status === 'Cancelled' ? '' : 'ok'}">${job.status === 'Cancelled' ? 'Stopped' : 'Done'} after ${esc(scanned)}.</div>
                ${renderBars(job.result?.Hits ?? job.hits)}
            </div>`
    }

    // A scan that still runs is resumed, otherwise the start button.
    if (null != app.jobs[key]) {
        await run(app.jobs[key])
        return
    }

    el.innerHTML = `
        <div class="card">
            <p>Reads all <strong>${esc(formatSize(disk.SizeBytes))}</strong> and counts file headers (photos, documents, archives, ...).</p>
            <p class="muted small">Takes as long as reading the disk once. You can leave this tab, the scan keeps running.</p>
            <button class="primary block" id="scan">Start deep scan</button>
        </div>`
    el.querySelector('#scan').addEventListener('click', () => { void run(null).catch(exception => app.toast(exception.message)) })
}

export default { id: TAB_ID, label: '🔍 Deep scan', jobType: 'DeepScan', render }
