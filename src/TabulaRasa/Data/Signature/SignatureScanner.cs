// NOTE:
//   Loaded by TabulaRasa.psm1 via Add-Type. The hot loop of the deep scan lives here,
//   because a PowerShell loop over every sector of a 1 TB disk (2 billion steps) takes days.

namespace TabulaRasa
{
    public static class SignatureScanner
    {
        /// <summary>
        /// Counts the sectors of a buffer that start with one of the given file headers.
        /// </summary>
        /// <param name="buffer">(Required) The bytes read from the disk.</param>
        /// <param name="length">(Required) The number of valid bytes in buffer.</param>
        /// <param name="sectorSize">(Required) The sector size, headers are only checked at sector starts.</param>
        /// <param name="magics">(Required) The magic bytes of every signature.</param>
        /// <param name="offsets">(Required) The position of the magic bytes inside the header, one per signature.</param>
        /// <param name="counts">(Required) One counter per signature, incremented on every match.</param>
        public static void CountSignatures(byte[] buffer, int length, int sectorSize, byte[][] magics, int[] offsets, long[] counts)
        {
            for (int sectorStart = 0; sectorStart < length; sectorStart += sectorSize)
            {
                for (int index = 0; index < magics.Length; index++)
                {
                    byte[] magic = magics[index];
                    int start = sectorStart + offsets[index];
                    if (start + magic.Length > length)
                    {
                        continue;
                    }

                    bool isMatch = true;
                    for (int position = 0; position < magic.Length; position++)
                    {
                        if (buffer[start + position] != magic[position])
                        {
                            isMatch = false;
                            break;
                        }
                    }
                    if (isMatch)
                    {
                        counts[index]++;
                    }
                }
            }
        }
    }
}
