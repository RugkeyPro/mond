<p align="right">
  <img align="right" height="140" src="https://github.com/rooootdev/mond/blob/main/mond.png?raw=true" style="float: right;"/>
</p>

<div style="width: calc(100% - 180px);">
  <h1 style="margin-bottom: 0;">mond</h1>
</div>

<p align="left">Edit MobileGestalt on iOS 27.0 beta 1 - 4!</p>

> [!WARNING]  
> Some of the tweaks have the potential to brick your device! Use at your own risk.

**Included in this build:**<br>
&#45; Editable browser for mond's Documents, Library and temporary directories<br>
&#45; Verified `/private/var` precise-path browser using bad_query on supported iOS builds<br>
&#45; Opt-in managed writes with automatic file backups before rename or deletion<br>
&#45; Files/iTunes document sharing for the Documents directory<br>

**Planned:**<br>
&#45; Pocket Poster

**Known Issues:**<br>
&#45; The `/private/var` root cannot be granted directly; the browser requests narrower real paths and reuses each grant for its descendants<br>
&#45; Real system files only appear when the selected path and installed iOS build are supported<br>
&#45; Write controls appear only after an independent write-access check; system directories and `com.apple.MobileGestalt.plist` remain protected from rename/delete<br>
&#45; Tweaks may disappear on reboot<br>
&#45; Apple Intelligence activation is broken<br>
&#45; Disable Region restrictions may be broken on some versions/devices<br>
&#45; iPadOS UI and related tweaks may not work and/or **bootloop** you!

**Credits:**<br>
&#45; [forcequit](https://github.com/forcequitOS) for his work on bad_query<br>
&#45; [johnny](https://github.com/0xjohnnydev) for his work on the MCM bug class<br>
&#45; [jailbreak.party](https://github.com/jailbreakdotparty) for PartyUI, GestaltView and the implementation of [neon](https://github.com/neonmodder123)'s respring method<br>

<i>btw, you should like totally star this repo and stuff</i>
