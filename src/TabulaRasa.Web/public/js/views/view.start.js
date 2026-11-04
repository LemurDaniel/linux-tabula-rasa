// NOTE:
//   Start screen. On the kiosk it shows how a phone reaches the stick (QR codes for the URL and
//   the hotspot), on every device it claims the control session or says who holds it.

//
//   Chapters:
//     START VIEW   QR codes on the kiosk, claiming the session.
//

import { request, claimSession } from '../utils/api.js'
import { esc } from '../utils/format.js'

const INFO_POLL_MS = 5000

// ===========================================================================
// =============================   START VIEW   ==============================
// ===========================================================================
//
//   wifiQrText   The Wi-Fi login as QR text, special characters escaped.
//   qrCard       One QR code with its caption.
//   render       Draws the screen from /api/info.
//   show         Renders, wires the start button and refreshes every few seconds.
//

// 'WIFI:T:WPA;S:<ssid>;P:<password>;;' with \ ; , : " escaped, the format phone cameras read.
function wifiQrText({ ssid, password }) {
    const escapeField = value => String(value).replace(/([\\;,:"])/g, '\\$1')
    return `WIFI:T:WPA;S:${escapeField(ssid)};P:${escapeField(password)};;`
}

function qrCard({ text, caption }) {
    return `
        <div class="qr">
            <img src="/api/qr?text=${encodeURIComponent(text)}" alt="QR code: ${esc(caption)}">
            <div class="qr-caption">${esc(caption)}</div>
        </div>`
}

function render({ info }) {
    const { network, session, isLocal } = info
    const hotspot = network.Hotspot

    // > Hotspot runs   join the Wi-Fi, open its address; LAN addresses as text below (second way)
    // > No hotspot     the LAN addresses as QR codes
    const lanUrls = network.Urls.filter(url => url !== hotspot?.Url)
    const isHotspot = hotspot?.IsActive && null != hotspot.Url
    const qrCodes = !isLocal
        ? ''
        : isHotspot
            ? `<div class="qr-grid">
                   ${qrCard({ text: wifiQrText({ ssid: hotspot.Ssid, password: hotspot.Password }), caption: `1. Wi-Fi: ${hotspot.Ssid} / ${hotspot.Password}` })}
                   ${qrCard({ text: hotspot.Url, caption: `2. ${hotspot.Url}` })}
               </div>
               <p class="muted">Scan both with your phone to control the stick from there.</p>
               ${lanUrls.length > 0 ? `<p class="muted small">Or over LAN: ${lanUrls.map(url => esc(url)).join(' · ')}</p>` : ''}`
            : `<div class="qr-grid">
                   ${lanUrls.slice(0, 2).map(url => qrCard({ text: url, caption: url })).join('')}
               </div>
               <p class="muted">Scan with your phone to control the stick from there.</p>`

    const lock = session.isLocked
        ? `<div class="notice">In use by <strong>${esc(session.ownerAddress)}</strong>, free in ${Math.ceil(session.secondsLeft / 60)} min.</div>`
        : ''

    const buttonLabel = session.isLocked && isLocal ? 'Take over control' : 'Start'
    const isDisabled = session.isLocked && !isLocal

    return `
        <section class="start">
            <div class="hero">📜</div>
            <h1>Tabula Rasa</h1>
            <p class="muted">Secure disk wipe. See what is still on a disk, then wipe it clean.</p>
            ${qrCodes}
            ${lock}
            <button id="start" class="primary block" ${isDisabled ? 'disabled' : ''}>${buttonLabel}</button>
            ${isLocal ? '<div style="margin-top:10px"><button id="console" class="ghost block">Text menu (tty2)</button></div>' : ''}
        </section>`
}

export default async function show({ app, navId }) {
    let info = await request({ path: '/api/info' })
    app.root.innerHTML = render({ info })

    // Delegated, the button survives the re-renders of the refresh below.
    app.root.onclick = async event => {
        // The way out of the kiosk: the server switches the screen to the text menu.
        if (event.target.id === 'console') {
            await request({ path: '/api/console', method: 'POST' }).catch(exception => app.toast(exception.message))
            return
        }
        if (event.target.id !== 'start') return
        const result = await claimSession({ isTakeover: info.isLocal && info.session.isLocked })
            .catch(exception => ({ isGranted: false, error: exception.message }))
        if (!result.isGranted) {
            app.toast(result.error ?? `In use by ${result.ownerAddress}.`)
            return
        }
        app.root.onclick = null
        await app.go('disks')
    }

    // Refresh: new IPs, the hotspot or a freed session show up without a reload.
    while (app.isCurrent(navId)) {
        await new Promise(resolve => setTimeout(resolve, INFO_POLL_MS))
        if (!app.isCurrent(navId)) break
        info = await request({ path: '/api/info' }).catch(() => info)
        app.root.innerHTML = render({ info })
    }
}
