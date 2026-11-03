// NOTE:
//   Files tab (stage 1): walks the folders of a partition. The server mounts it read-only
//   for every request and unmounts it again, nothing can be opened or copied.

import { request } from '../../utils/api.js'
import { esc, formatSize, formatDate } from '../../utils/format.js'
import { loadPartitions, renderPartitionSelect } from '../../utils/partitions.js'

const TAB_ID = 'files'

// ===========================================================================
// ==============================   FILES TAB   ==============================
// ===========================================================================
//
//   renderBreadcrumb   The path as buttons back to every parent folder.
//   renderEntries      Folders (clickable) and files with size and date.
//   render             Partition picker, then one folder at a time.
//

function renderBreadcrumb(path) {
    const parts = path.split('/').filter(Boolean)
    const buttons = parts
        .map((part, index) => `<button class="ghost" data-path="${esc(parts.slice(0, index + 1).join('/'))}">${esc(part)}</button>`)
        .join('')
    return `<div class="breadcrumb"><button class="ghost" data-path="">/</button>${buttons}</div>`
}

function renderEntries({ entries, totalCount }) {
    if (entries.length === 0) return '<p class="muted">This folder is empty.</p>'

    const rows = entries
        .map(entry => entry.IsDirectory
            ? `<li class="folder" data-path="${esc(entry.RelativePath)}"><span class="name">📁 ${esc(entry.Name)}</span><span class="meta">›</span></li>`
            : `<li><span class="name">${entry.IsLink ? '🔗' : '📄'} ${esc(entry.Name)}</span><span class="meta">${esc(formatSize(entry.SizeBytes))} · ${esc(formatDate(entry.LastWriteTime))}</span></li>`)
        .join('')
    const more = totalCount > entries.length ? `<p class="muted small">Showing ${entries.length} of ${totalCount} entries.</p>` : ''
    return `<ul class="list">${rows}</ul>${more}`
}

async function render({ app, disk, el, navId }) {
    el.innerHTML = '<div class="card"><span class="spinner"></span>Reading partitions ...</div>'
    const partitions = await loadPartitions({ disk, isMountableOnly: true })
    if (!app.isCurrent(navId)) return

    if (partitions.length === 0) {
        el.innerHTML = '<div class="notice">No readable partition. The Deleted tab or the deep scan may still find data.</div>'
        return
    }

    let partition = partitions[0].Name

    const open = async path => {
        const listing = el.querySelector('#listing')
        listing.innerHTML = '<span class="spinner"></span>Reading ...'
        try {
            const query = new URLSearchParams({ partition, path })
            const result = await request({ path: `/api/disks/${encodeURIComponent(disk.Name)}/browse?${query}` })
            if (!app.isCurrent(navId)) return
            listing.innerHTML = renderBreadcrumb(path) + renderEntries(result)
        } catch (exception) {
            listing.innerHTML = `<div class="notice error">${esc(exception.message)}</div>`
            throw exception
        }
    }

    el.innerHTML = `
        <div class="card">
            ${partitions.length > 1 ? renderPartitionSelect({ partitions, selected: partition }) : `<p class="muted mono">${esc(partitions[0].Path)} · ${esc(partitions[0].FileSystem)}</p>`}
            <div id="listing"></div>
        </div>`

    el.querySelector('#partition')?.addEventListener('change', event => {
        partition = event.target.value
        void open('').catch(() => null)
    })
    el.querySelector('#listing').addEventListener('click', event => {
        const target = event.target.closest('[data-path]')
        if (null == target) return
        void open(target.dataset.path).catch(() => null)
    })

    await open('')
}

export default { id: TAB_ID, label: '📁 Files', render }
