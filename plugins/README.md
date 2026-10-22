# Plugin sources

The sources in this directory are what Spotube bundles. `scripts/build-radio-plugin.sh`
compiles them into the `.smplug` archives under `assets/plugins/`, and the app
installs those archives on first launch.

Both radio plugins are also published on their own, which is where the canonical
source lives:

| Plugin | Standalone repository | Install URL |
| --- | --- | --- |
| Internet Radio Browser | [Adamyabhatt01/spotube-plugin-internet-radio-browser](https://github.com/Adamyabhatt01/spotube-plugin-internet-radio-browser) | `https://raw.githubusercontent.com/Adamyabhatt01/spotube-plugin-internet-radio-browser/1.0.1/dist/plugin.smplug` |
| Internet Radio SomaFM | [Adamyabhatt01/spotube-plugin-internet-radio-somafm](https://github.com/Adamyabhatt01/spotube-plugin-internet-radio-somafm) | `https://raw.githubusercontent.com/Adamyabhatt01/spotube-plugin-internet-radio-somafm/1.0.1/dist/plugin.smplug` |

The copy here is what the bundled artifact is built from, so the two are kept in
step by bumping `version` in `plugin.json` and rebuilding:

```bash
scripts/build-radio-plugin.sh                       # every plugin here
scripts/build-radio-plugin.sh internet-radio-browser # one of them
```

The compiler is pinned: `hetu_script_dev_tools 0.1.0+2` is the release that ships
`hetu_script 0.4.2+1`, the version Spotube's own Hetu VM runs. A newer dev-tools
release compiles with `hetu_script 0.6.x` and emits bytecode the app cannot load.
