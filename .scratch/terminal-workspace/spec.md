Status: ready-for-agent

## Problem Statement

Opening separate terminal windows and switching between them interrupts the user's work. The user wants several live terminals visible together on a Mac, with quick ways to focus, rearrange, and move them between monitors. They also want a keyboard-driven experience inspired by Omarchy without losing direct mouse controls.

## Solution

Build a downloadable, open-source macOS terminal app that starts with one terminal and adds terminals to the same window. Up to four live terminal panes share a workspace. Additional terminals open in another workspace within that window. Users can resize and rearrange panes, move a live pane to another window or monitor by dragging, and control panes and workspaces with configurable shortcuts. Each window has its own workspaces. A settings icon opens preferences. The app restores layouts and working directories on relaunch with fresh shell sessions.

## User Stories

1. As a Mac user, I want to launch a dedicated terminal app, so that my terminal sessions share one managed workspace.
2. As a Mac user, I want the app to open with one terminal, so that I can start working immediately.
3. As a Mac user, I want a visible plus button to add a terminal, so that creating a pane is easy to discover.
4. As a keyboard user, I want a shortcut to add a terminal, so that I can keep my hands on the keyboard.
5. As a Mac user, I want a new terminal to join the current window, so that I do not have to switch between separate terminal windows.
6. As a Mac user, I want terminals placed in a predictable top-left, top-right, bottom-left, bottom-right order, so that I can anticipate where a new pane appears.
7. As a Mac user, I want up to four terminals visible in one workspace, so that I can monitor them simultaneously.
8. As a Mac user, I want a fifth terminal to open in another workspace in the same window, so that the visible panes remain usable.
9. As a Mac user, I want a visible workspace switcher, so that I can find and open a different group of terminals.
10. As a keyboard user, I want shortcuts to switch workspaces, so that I can move between terminal groups quickly.
11. As a Mac user, I want each app window to have its own workspaces, so that windows on different monitors can show different terminal groups.
12. As a Mac user, I want equal pane sizes initially, so that the layout is useful without configuration.
13. As a Mac user, I want to resize panes by dragging dividers, so that important output has more room.
14. As a Mac user, I want each workspace to remember its pane sizes, so that my arrangement stays useful when I return.
15. As a Mac user, I want the remaining panes to expand after a pane closes, so that the workspace has no empty cell.
16. As a Mac user, I want to drag panes to rearrange them, so that I can put terminals where I want them.
17. As a Mac user, I want to drag a pane into another window or monitor, so that its terminal appears where I need it.
18. As a Mac user, I want to drag a pane out onto the desktop or another monitor to create a new window, so that I can spread work across screens.
19. As a Mac user, I want a moved terminal to keep its running command and scrollback, so that moving a pane never interrupts work.
20. As a Mac user, I want a pane dropped into a full workspace to create another workspace in the destination window, so that no existing pane is displaced.
21. As a keyboard user, I want to focus neighboring panes by direction, so that I can navigate without a mouse.
22. As a keyboard user, I want to swap panes and send a pane to another workspace with shortcuts, so that disabling drag and drop remains practical.
23. As a Mac user, I want drag and drop enabled initially, so that rearrangement works without setup.
24. As a keyboard user, I want to disable pane drag and drop in settings, so that the app fits my preferred workflow.
25. As a Mac user, I want to expand one pane temporarily, so that I can concentrate on a task.
26. As a Mac user, I want Escape to restore the prior split layout while a pane is expanded, so that returning to four visible terminals is immediate.
27. As a terminal user, I want Escape passed to the running program outside focus mode, so that terminal applications work normally.
28. As a terminal user, I want a new pane to inherit the selected pane's working directory, so that I can work in the same project immediately.
29. As a terminal user, I want a new pane to start in my home directory when there is no selected pane, so that it has a predictable starting point.
30. As a terminal user, I want ordinary shell behavior, copy and paste, scrolling, links, and colors, so that my existing command-line tools remain usable.
31. As a Mac user, I want a customizable app-wide shortcut to bring forward my most recently used terminal window, so that I can reach it from another app without creating a pane.
32. As a Mac user, I want a small settings icon, so that I can find the app's preferences.
33. As a Mac user, I want to customize keybindings, so that the app fits my keyboard and avoids shortcut conflicts.
34. As a Mac user, I want settings for terminal behavior, pane management, and layouts, so that I can adapt the app to my workflow.
35. As a Mac user, I want settings saved locally, so that my preferences persist across launches.
36. As a Mac user, I want confirmation before closing a pane with a running command, so that I cannot terminate work accidentally.
37. As a Mac user, I want a pane to close only after I explicitly confirm that warning, so that dismissing the dialog preserves the session.
38. As a Mac user, I want closing a window to protect its running commands while leaving other windows' sessions alone, so that I can close one group safely.
39. As a Mac user, I want quitting the app to warn about running commands, so that I understand that quitting will end every session.
40. As a Mac user, I want the app to restore my windows, workspaces, layouts, and directories on relaunch, so that I can resume my arrangement quickly.
41. As a Mac user, I want restored panes to start fresh shells, so that relaunch behavior is predictable.
42. As an open-source contributor, I want the app's terminal foundation and workspace behavior kept as separate concerns, so that later requirements can be added or changed.

## Implementation Decisions

- The first release is a dedicated macOS terminal app for Apple Silicon. It will be open source and downloadable; broader Mac compatibility can follow.
- Reuse an existing terminal implementation for terminal emulation rather than building terminal emulation from scratch. Choose a macOS-compatible foundation during implementation; no library has been selected yet.
- Keep terminal sessions independent of their visual pane placement. Moving a pane between positions, workspaces, windows, or monitors transfers the same live session and scrollback; it does not restart the process.
- Start with one pane. Add panes in top-left, top-right, bottom-left, then bottom-right order, up to four per workspace. Additional new panes create another workspace within the same window.
- Start with equal pane sizes. Dividers resize panes, and each workspace retains its adjusted layout. Closing a pane lets the remaining panes fill the space.
- Each window owns its own workspaces and presents a visible way to switch among them. A pane dropped into a destination workspace with four panes is placed in a new workspace in that destination window.
- Dragging a pane outside its window creates a new window around the same live session. Dragging into another window moves that session to the destination window; the window can be on another physical monitor.
- Drag and drop is enabled by default and can be disabled in preferences. Keyboard operations cover directional focus, swapping panes, and moving panes between workspaces. Exact default key combinations remain a design choice, subject to macOS conflicts and customization.
- A customizable app-wide shortcut raises the most recently used terminal window without creating a pane. Pane and workspace shortcuts act while the app is active.
- Focus mode expands one pane while retaining its prior layout. Escape exits focus mode and is consumed by the app; otherwise Escape is delivered to the terminal program.
- A new terminal inherits the selected terminal's current working directory; if there is no selected terminal, it uses the user's home directory.
- Closing a pane with a running command requires an explicit confirmation. Closing a window applies that protection to its sessions and does not affect other windows. Quitting checks all running commands, then ends all sessions if confirmed.
- Persist preferences locally. On relaunch, restore window and workspace structure, pane arrangement and sizes, and working directories, then start fresh shells. Running processes are not preserved across a quit.
- Settings are accessible through a small icon and cover keybindings, terminal behavior, pane management, and layout preferences.
- Use Omarchy's documented keyboard navigation and workspace interactions as a user-experience reference, adapted to macOS and to terminal panes. Omarchy's Linux window-manager implementation is not the app foundation.

## Testing Decisions

- Prefer one high-level seam: exercise the running app through user actions while panes use real shell sessions. Assert visible behavior and process continuity, not private layout data structures or implementation details.
- Verify the one-to-four pane sequence, the fifth pane's new workspace, workspace switching, pane resizing, closing a pane, and space reclamation.
- Verify that dragging a pane within a window, between windows, and onto another monitor or the desktop preserves its running process and visible history. Verify the full-destination behavior.
- Verify keyboard navigation, swapping, moving between workspaces, configurable bindings, drag-and-drop disablement, the app-wide raise shortcut, and the visible settings entry point.
- Verify focus mode, Escape restoration, and delivery of Escape to a terminal program outside focus mode.
- Verify current-directory inheritance, local preferences persistence, and relaunch restoration with fresh shells.
- Verify that canceling a close or quit warning preserves running sessions, and that confirmation closes only the intended sessions.
- Verify basic terminal compatibility with representative shell commands and interactive terminal programs, including copy and paste, scrolling, links, and colors.
- There is no existing test suite or similar prior art in this empty project. Multi-monitor gestures and other platform-sensitive interactions require testing on the target Mac in addition to automated coverage.

## Out of Scope

- Tiling unrelated macOS apps or replacing the macOS window manager.
- Keeping shell processes alive after the app quits.
- Synchronizing settings between Macs or exporting and importing them in the first release.
- Intel Mac support in the first release.
- Reproducing Omarchy's Linux desktop, compositor, or complete feature set.

## Further Notes

- The target development machine is Apple Silicon running macOS 26.6.2. The project started as an empty directory with no existing application or tests.
- Omarchy references: https://omarchy.org/manual/navigation/ and https://omarchy.org/manual/terminal/.
- The repo setup skill was deferred by the user. The agreed issue tracker is local Markdown, and this spec uses the agreed `ready-for-agent` triage status. Agent instruction and domain configuration files can be completed later.
