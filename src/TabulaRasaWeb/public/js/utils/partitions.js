// NOTE:
//   Partition picker shared by the Files and the Deleted tab.

import { request } from './api.js'
import { esc, formatSize } from './format.js'

// ===========================================================================
// ===========================   PARTITION PICKER   ==========================
// ===========================================================================
//
//   loadPartitions          Partitions of a disk, optionally only mountable ones.
//   renderPartitionSelect   A select with one option per partition.
//

export async function loadPartitions({ disk, isMountableOnly = false }) {
    const { partitions } = await request({ path: `/api/disks/${encodeURIComponent(disk.Name)}/partitions` })
    return partitions.filter(partition => !isMountableOnly || partition.IsMountable)
}

export function renderPartitionSelect({ partitions, selected }) {
    const options = partitions
        .map(partition => {
            const label = [partition.Path, partition.FileSystem || 'no file system', formatSize(partition.SizeBytes), partition.Label]
                .filter(Boolean)
                .join(' · ')
            return `<option value="${esc(partition.Name)}" ${partition.Name === selected ? 'selected' : ''}>${esc(label)}</option>`
        })
        .join('')
    return `<select id="partition" aria-label="Partition">${options}</select>`
}
