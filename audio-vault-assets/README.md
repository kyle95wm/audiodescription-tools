# AudioVault Assets

This folder is expected to contain:

- `bumper.mp3` – The official AudioVault intro bumper
- `silence_1s.mp3` – One second of silence for padding

These are required by the `audiovault_master.py` script to prepend a short intro before the mastered audio file.

---

## 🔗 Download Instructions

You can download the assets directly from this repo:

- [bumper.mp3](./bumper.mp3)
- [silence_1s.mp3](./silence_1s.mp3)

The script will look for these files in:

```
~/audio-vault-assets/bumper.mp3
~/audio-vault-assets/silence_1s.mp3
```

If `silence_1s.mp3` is missing, the script will auto-generate it.  
If `bumper.mp3` is missing, the script will exit with an error.
