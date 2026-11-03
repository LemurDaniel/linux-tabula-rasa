// NOTE:
//   Deleted tab (stage 2): files the file system marks deleted but still holds (sleuthkit).

//
//   Chapters:
//     DELETED TAB   Partition picker and the deleted files.
//

import { runJob, pollJob } from '../../utils/api.js'
import { esc, formatSize, formatDate } from '../../utils/format.js'
import { loadPartitions, renderPartitionSelect } from '../../utils/partitions.js'

const TAB_ID = 'deleted'
const LIST_LIMIT = 300

// ===========================================================================
// =============================   DELETED TAB   =============================
// ===========================================================================
//
//   renderResult   Count, size and the first files, or why nothing could be read.
//   render         Partition picker and the read button.
//

function renderResult(result) {
    if (!result.IsSupported) {
        return '<div class="notice">The file system cannot be read (quick formatted, encrypted or unknown). The deep scan still finds file headers.</div>'
    }
    if (result.TotalCount === 0) {
        return '<div class="notice ok">No deleted files found in the file system.</div>'
    }

    const files = result.Files.slice(0, LIST_LIMIT)
    const totalBytes = result.Files.reduce((sum, file) => sum + file.SizeBytes, 0)
    const rows = files
        .map(file => `<li><span class="name mono">${esc(file.Path)}</span><span class="meta">${esc(formatSize(file.SizeBytes))} · ${esc(formatDate(file.LastWriteTime))}</span></li>`)
        .join('')

    return `
        <div class="notice">${esc(result.TotalCount)} deleted files, the first ${esc(result.Files.length)} hold ${esc(formatSize(totalBytes))}.</div>
        <ul class="list">${rows}</ul>
        ${result.TotalCount > files.length ? `<p class="muted small">Showing ${files.length} of ${result.TotalCount}.</p>` : ''}`
}

async function render({ app, disk, el, navId }) {
    el.innerHTML = '<div class="card"><span class="spinner"></span>Reading partitions ...</div>'
    const partitions = (await loadPartitions({ disk })).filter(partition => partition.FileSystem)
    if (!app.isCurrent(navId)) return

    if (partitions.length === 0) {
        el.innerHTML = '<div class="notice">No partition with a file system. The deep scan still finds file headers.</div>'
        return
    }

    const key = app.jobKey(disk.Name, 'Deleted')
    el.innerHTML = `
        <div class="card">
            <p class="muted">Reads the file system metadata, the partition is not mounted.</p>
            ${renderPartitionSelect({ partitions, selected: partitions[0].Name })}
            <div style="margin-top:10px"><button class="primary block" id="read">Find deleted files</button></div>
        </div>
        <div id="result"></div>`

    const resultElement = el.querySelector('#result')
    const read = async jobId => {
        resultElement.innerHTML = '<div class="card"><span class="spinner"></span>Reading the file system ...</div>'
        const partition = el.querySelector('#partition').value
        const job = null != jobId
            ? await pollJob({ id: jobId })
            : await runJob({ body: { type: 'Deleted', disk: disk.Name, partition }, control: { set jobId(id) { app.jobs[key] = id } } })
        delete app.jobs[key]

        if (!app.isCurrent(navId)) return
        resultElement.innerHTML = job.status === 'Done'
            ? renderResult(job.result)
            : `<div class="notice error">${esc(job.error ?? job.status)}</div>`
    }

    el.querySelector('#read').addEventListener('click', () => { void read(null).catch(exception => app.toast(exception.message)) })
    if (null != app.jobs[key]) await read(app.jobs[key])
}

export default { id: TAB_ID, label: '🗑️ Deleted', render }
