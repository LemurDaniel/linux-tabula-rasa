// NOTE:
//   Overview tab (stage 1): partitions with usage, sampled blocks and a quick file header estimate.

//
//   Chapters:
//     OVERVIEW TAB   Runs or resumes the overview and shows it.
//

import { runJob, pollJob } from '../../utils/api.js'
import { esc, formatSize, renderBars } from '../../utils/format.js'

const TAB_ID = 'overview'

// ===========================================================================
// ============================   OVERVIEW TAB   =============================
// ===========================================================================
//
//   renderResult   Partition table, samples and the bar chart.
//   render         Runs the job (or resumes it) and shows the result.
//

function renderResult(result) {
    const partitionRows = result.Partitions
        .map(partition => `
            <tr>
                <td class="mono">${esc(partition.Path)}</td>
                <td>${esc(partition.FileSystem || 'none')}</td>
                <td>${esc(partition.Label)}</td>
                <td>${esc(formatSize(partition.SizeBytes))}</td>
                <td>${null == partition.UsedBytes ? `<span class="muted">${esc(partition.State)}</span>` : esc(formatSize(partition.UsedBytes))}</td>
            </tr>`)
        .join('')

    const partitions = result.Partitions.length > 0
        ? `<div class="table-wrap"><table>
               <thead><tr><th>Partition</th><th>File system</th><th>Label</th><th>Size</th><th>Used</th></tr></thead>
               <tbody>${partitionRows}</tbody>
           </table></div>`
        : '<div class="notice">No partitions found, maybe quick formatted or never partitioned. The deep scan still finds old files.</div>'

    const samples = result.Samples
    const sampleNotice = samples.HasData
        ? `<div class="notice">${esc(samples.NonZeroCount)} of ${esc(samples.SampleCount)} sampled blocks hold data.</div>`
        : `<div class="notice ok">All ${esc(samples.SampleCount)} sampled blocks are empty.</div>`

    return `
        <div class="card">
            <h2>Partitions</h2>
            ${partitions}
        </div>
        <div class="card">
            <h2>Samples</h2>
            ${sampleNotice}
            <h2>File headers in ${esc(formatSize(result.Signatures.BytesScanned))} of samples</h2>
            <p class="muted small">An estimate. The deep scan reads the whole disk.</p>
            ${renderBars(result.Signatures.Hits)}
        </div>
        <button class="block" id="rerun">Read again</button>`
}

async function render({ app, disk, el, navId }) {
    const key = app.jobKey(disk.Name, 'Overview')

    const start = async () => {
        el.innerHTML = '<div class="card"><span class="spinner"></span>Reading partitions and samples ...</div>'
        const job = null != app.jobs[key]
            ? await pollJob({ id: app.jobs[key] })
            : await runJob({ body: { type: 'Overview', disk: disk.Name }, control: { set jobId(id) { app.jobs[key] = id } } })
        delete app.jobs[key]

        if (!app.isCurrent(navId)) return
        if (job.status !== 'Done') {
            el.innerHTML = `<div class="notice error">${esc(job.error ?? job.status)}</div>`
            return
        }
        app.cache[key] = job.result
        el.innerHTML = renderResult(job.result)
        el.querySelector('#rerun').addEventListener('click', () => start())
    }

    // A cached result shows right away, a new read only on request.
    if (null != app.cache[key] && null == app.jobs[key]) {
        el.innerHTML = renderResult(app.cache[key])
        el.querySelector('#rerun').addEventListener('click', () => start())
        return
    }
    // Another job runs (one at a time): no automatic read, it would only be refused.
    const otherJob = app.runningJobs.find(job => app.jobKey(job.disk, job.type) !== key)
    if (null == app.jobs[key] && null != otherJob) {
        el.innerHTML = `
            <div class="notice">A ${esc(app.jobName(otherJob.type))} on ${esc(otherJob.disk)} is still running, only one job runs at a time.</div>
            <button class="block" id="rerun">Read anyway</button>`
        el.querySelector('#rerun').addEventListener('click', () => { void start().catch(exception => app.toast(exception.message)) })
        return
    }
    await start()
}

export default { id: TAB_ID, label: '📊 Overview', jobType: 'Overview', render }
