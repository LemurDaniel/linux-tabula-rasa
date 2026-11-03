// NOTE:
//   Disk list. Refreshes every few seconds, so a plugged in stick shows up on its own.

import { request } from '../utils/api.js'
import { esc, formatSize, kindIcon, kindName } from '../utils/format.js'

const DISK_POLL_MS = 3000

// ===========================================================================
// =============================   DISKS VIEW   ==============================
// ===========================================================================
//
//   diskCard   One disk with kind, size, serial and the wipe method.
//   render     All disks, or a hint when there is none.
//   show       Renders, opens a disk on click and refreshes while visible.
//

function diskCard(disk) {
    const wipe = disk.Wipe
    return `
        <div class="card clickable" tabindex="0" data-disk="${esc(disk.Name)}">
            <div class="disk-head">
                <div class="disk-icon">${kindIcon(disk.Kind)}</div>
                <div>
                    <div class="disk-title">${esc(disk.Model || disk.Name)}</div>
                    <div class="muted small mono">${esc(disk.Path)} · ${esc(disk.Serial || 'no serial')}</div>
                </div>
            </div>
            <span class="badge">${esc(kindName(disk.Kind))}</span>
            <span class="badge">${esc(formatSize(disk.SizeBytes))}</span>
            <span class="badge ${wipe.IsComplete ? 'ok' : 'warn'}">${esc(wipe.Method)}</span>
        </div>`
}

function render({ disks }) {
    const list = disks.length > 0
        ? disks.map(diskCard).join('')
        : '<div class="notice">No disks found. Plug one in, it shows up here on its own.</div>'

    return `
        <h1>Disks</h1>
        <p class="muted">The stick itself is hidden. Pick a disk to see what is on it.</p>
        ${list}`
}

export default async function show({ app, navId }) {
    let { disks } = await request({ path: '/api/disks' })
    let rendered = JSON.stringify(disks)
    app.root.innerHTML = render({ disks })

    const open = event => {
        const card = event.target.closest('[data-disk]')
        if (null == card) return
        if (event.type === 'keydown' && event.key !== 'Enter') return
        const disk = disks.find(item => item.Name === card.dataset.disk)
        void app.go('disk', { disk, tab: 'overview' })
    }
    app.root.onclick = open
    app.root.onkeydown = open

    while (app.isCurrent(navId)) {
        await new Promise(resolve => setTimeout(resolve, DISK_POLL_MS))
        if (!app.isCurrent(navId)) break

        ;({ disks } = await request({ path: '/api/disks' }))
        // Only re-render on a change, a re-render would steal the keyboard focus.
        if (JSON.stringify(disks) !== rendered) {
            rendered = JSON.stringify(disks)
            app.root.innerHTML = render({ disks })
        }
    }
}
