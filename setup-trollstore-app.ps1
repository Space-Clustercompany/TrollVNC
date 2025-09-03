$vf = "src/moonlight/gs_video_vt.mm"
(Get-Content $vf -Raw) `
  -replace 'self->_vps.bytes','(const uint8_t*)self->_vps.bytes' `
  -replace 'self->_sps.bytes','(const uint8_t*)self->_sps.bytes' `
  -replace 'self->_pps.bytes','(const uint8_t*)self->_pps.bytes' `
| Set-Content $vf -NoNewline
git add $vf
git commit -m "Fix: cast NSData.bytes to const uint8_t* in VT encoder"
git push
