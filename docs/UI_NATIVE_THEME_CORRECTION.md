# Native template appearance correction

Bash's screenshots show stock red My Builds/Max buttons, the stock Orb maximum input border, and the HUD retaining its old backdrop beside a selected orange Orb window. This correction addresses those appearance differences. It is not a performance fix.

The client 3.3.5.12340 SharedUIPanelTemplates override defines Left, Middle and Right stock button texture regions. Normal/pushed/disabled texture setters do not remove these separate regions. Native state scripts change their texture files. Theme styling now hides only regions with recognized stock button paths once, preserving their zero alpha across state changes. Custom icons, labels, existing handlers, input gates and hover textures remain owned by their existing controls. Native IsEnabled returns 0/1; repainting treats 0 as disabled.

Only the Orb approved maximum input opts into input styling. Its recognized Common-Input-Border regions are suppressed once and its backdrop joins the selected palette. A one-time six-unit inset on each side keeps text clear of the new inside border, leaving 53 units in the 65-unit box for the five-digit maximum. Input validation, five-character limit, focus behavior and approval state are unchanged. Other EditBoxes are not discovered or styled by a tree walk. Native font clearance still requires client verification.

The main HUD window joins the existing appearance registry. The marked replacement difficulty/Soul Ash card keeps its existing layout, fonts and backdrop. No gameplay, protocol, persistence schema, spending or automation code changes.

`ui_theme_native_templates` loads the actual TOC/panels with synthetic data and models native texture regions, FontString objects and 0/1 enabled states. It checks state transitions, palette repainting, protected-card preservation, custom-icon preservation and repeated-refresh allocation bounds. This is a source/template test, not native rendering evidence. The default harness does not render fonts or pixels.

Native acceptance still requires the installed client: enabled/disabled/hover/press/reopen states, all palettes, long labels, input focus and validation, scrolling, UI scaling, window resize, dragging, and unchanged difficulty/Soul Ash card. FPS and frame-time comparisons must use matched conditions with automation OFF. Synthetic source timings cannot establish the cause of an addon ON/OFF FPS loss.
