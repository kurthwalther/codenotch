# This fork

A personal build of [vinzdg/codenotch](https://github.com/vinzdg/codenotch)
with changes that stay here: rings that show what is *left*, a second
window as a bar above the ring, a keep-awake handle, notes when an agent
finishes, a conversation card with a reply line, and a good deal more. See
the commit log for the lot.

## Install on a Mac

1. Install Xcode (the App Store one or a beta) and open it once.
   Sign in with any Apple ID under Settings › Accounts, so Xcode makes an
   *Apple Development* certificate. A free account is enough.
2. `brew install xcodegen`
3. Clone this fork and run the installer:

       git clone https://github.com/kurthwalther/codenotch.git
       cd codenotch
       Scripts/install-local.sh

   It builds a Release configuration signed with that certificate — or ad
   hoc, if there is none — and puts it in `/Applications`, moving any copy
   already there to the Trash.
4. In the app: Settings › General › *Open Codenotch at login*. When macOS
   asks about Claude Code's keychain item, choose **Always Allow**.
5. Replying to sessions from the card needs super.engineering with
   *Settings › Experimental › Agent orchestration* on.

Copying the built `.app` to another Mac also works, but that Mac will ask
you to allow it under System Settings › Privacy & Security the first time,
and the keychain permission has to be granted there too.

`Scripts/install-local.sh --test` runs the unit tests; `--build` builds
without installing.

## Keeping up with the author

Sparkle's automatic updates are switched off in this fork on purpose: the
author's feed serves his build, which would replace this one. Updates come
through git instead:

    git fetch upstream            # upstream = https://github.com/vinzdg/codenotch.git
    git merge upstream/main       # his new commits underneath, ours on top
    Scripts/install-local.sh --test
    Scripts/install-local.sh

Where his changes and ours touch the same lines, git stops and asks; that
is the moment to resolve them, run the tests, and install.
