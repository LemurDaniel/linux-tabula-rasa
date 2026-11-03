# File headers searched by Find-TabulaRasaFileSignature at the start of every 512-byte sector.
# Offset is the position of the magic bytes inside the header, Magic is hex.
@{
    Signatures = @(
        @{ Type = 'JPEG';                    Offset = 0; Magic = 'FFD8FF' }
        @{ Type = 'PNG';                     Offset = 0; Magic = '89504E470D0A1A0A' }
        @{ Type = 'GIF';                     Offset = 0; Magic = '47494638' }
        @{ Type = 'PDF';                     Offset = 0; Magic = '255044462D' }
        @{ Type = 'ZIP / Office (docx, xlsx)'; Offset = 0; Magic = '504B0304' }
        @{ Type = 'Office (doc, xls)';       Offset = 0; Magic = 'D0CF11E0A1B11AE1' }
        @{ Type = 'MP4 / MOV / HEIC';        Offset = 4; Magic = '66747970' }
        @{ Type = 'RIFF (AVI, WAV, WebP)';   Offset = 0; Magic = '52494646' }
        @{ Type = 'MP3';                     Offset = 0; Magic = '494433' }
        @{ Type = 'SQLite';                  Offset = 0; Magic = '53514C69746520666F726D6174203300' }
        @{ Type = 'RAR';                     Offset = 0; Magic = '526172211A07' }
        @{ Type = '7z';                      Offset = 0; Magic = '377ABCAF271C' }
    )
}
