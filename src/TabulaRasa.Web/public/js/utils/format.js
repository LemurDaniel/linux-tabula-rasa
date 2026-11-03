// NOTE:
//   Formatting helpers of the web UI. Every text from the server goes through esc() before it
//   lands in innerHTML: model names, file names and labels come from disks, not from us.

//
//   Chapters:
//     HELPERS   Escaping, sizes, dates, disk kinds, bar chart.
//

const SIZE_UNITS = ['B', 'KB', 'MB', 'GB', 'TB', 'PB']
const KIND_ICONS = { Hdd: '💽', SataSsd: '💾', Nvme: '⚡', Usb: '🔌', SdCard: '🗂️', Unknown: '❔' }
const KIND_NAMES = { Hdd: 'HDD', SataSsd: 'SATA SSD', Nvme: 'NVMe', Usb: 'USB', SdCard: 'SD card', Unknown: 'Unknown' }

// ===========================================================================
// ===============================   HELPERS   ===============================
// ===========================================================================
//
//   esc          Escapes text for innerHTML.
//   formatSize   Decimal units as on disk labels, 500107862016 => '500.1 GB'.
//   formatDate   ISO date => 'yyyy-mm-dd', empty for none.
//   kindIcon     Emoji per disk kind.
//   kindName     Readable name per disk kind.
//   renderBars   Bar chart of signature hits.
//

export function esc(text) {
    return String(text ?? '')
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;')
}

export function formatSize(bytes) {
    if (null == bytes) return ''
    let value = Number(bytes)
    let unit = 0
    while (value >= 1000 && unit < SIZE_UNITS.length - 1) {
        value /= 1000
        unit++
    }
    return unit === 0 ? `${bytes} B` : `${value.toFixed(1)} ${SIZE_UNITS[unit]}`
}

export function formatDate(value) {
    if (null == value) return ''
    const date = new Date(value)
    return Number.isNaN(date.getTime()) ? '' : date.toISOString().slice(0, 10)
}

export function kindIcon(kind) {
    return KIND_ICONS[kind] ?? KIND_ICONS.Unknown
}

export function kindName(kind) {
    return KIND_NAMES[kind] ?? kind
}

export function renderBars(hits) {
    const list = hits ?? []
    if (list.length === 0) return '<p class="muted">No file headers found.</p>'

    const max = Math.max(...list.map(hit => hit.Count))
    const rows = list
        .map(hit => `
            <div class="bar">
                <span>${esc(hit.Type)}</span>
                <div class="bar-track"><div class="bar-fill" style="width:${Math.max(2, Math.round(100 * hit.Count / max))}%"></div></div>
                <strong>${esc(hit.Count)}</strong>
            </div>`)
        .join('')
    return `<div class="bars">${rows}</div>`
}
