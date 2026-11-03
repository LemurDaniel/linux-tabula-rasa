// NOTE:
//   One disk: a header and the tabs of the data views and the wipe (views/disk/).

import { esc, formatSize, kindIcon, kindName } from '../utils/format.js'

import tabs from './disk/_index.js'

// ===========================================================================
// ==============================   DISK VIEW   ==============================
// ===========================================================================
//
//   render   Header with back button and the tab bar.
//   show     Renders the frame and hands the content area to the active tab.
//

function render({ disk, activeTab }) {
    const tabButtons = tabs
        .map(tab => `<button data-tab="${tab.id}" class="${tab.id === activeTab ? 'active' : ''} ${tab.isDanger ? 'tab-danger' : ''}">${tab.label}</button>`)
        .join('')

    return `
        <button class="ghost" id="back">← Disks</button>
        <div class="disk-head" style="margin-top:12px">
            <div class="disk-icon">${kindIcon(disk.Kind)}</div>
            <div>
                <h1 style="margin:0">${esc(disk.Model || disk.Name)}</h1>
                <div class="muted small mono">${esc(disk.Path)} · ${esc(kindName(disk.Kind))} · ${esc(formatSize(disk.SizeBytes))} · ${esc(disk.Serial || 'no serial')}</div>
            </div>
        </div>
        <nav class="tabs">${tabButtons}</nav>
        <section id="tab"></section>`
}

export default async function show({ app, params, navId }) {
    const { disk } = params
    const activeTab = params.tab ?? 'overview'
    const tab = tabs.find(item => item.id === activeTab) ?? tabs[0]

    app.root.innerHTML = render({ disk, activeTab: tab.id })
    app.root.onclick = null
    app.root.onkeydown = null

    app.root.querySelector('#back').addEventListener('click', () => app.go('disks'))
    app.root.querySelectorAll('[data-tab]').forEach(button => {
        button.addEventListener('click', () => app.go('disk', { disk, tab: button.dataset.tab }))
    })
    // On a phone the tab bar scrolls, the active tab must stay in sight.
    app.root.querySelector('.tabs .active')?.scrollIntoView({ inline: 'center', block: 'nearest' })

    await tab.render({ app, disk, el: app.root.querySelector('#tab'), navId })
}
