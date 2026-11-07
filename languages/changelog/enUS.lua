-- LizeUI - Changelog (English)
-- Ordered list from the newest version to the oldest.
-- Line format:
--   "- text"   -> bullet point
--   "# text"   -> subtitle
--   ""         -> blank line

local _, ns = ...
ns.Changelogs = ns.Changelogs or {}

ns.Changelogs.en = {
    {
        version = "2.0.0",
        date = "11/07/2026",
        title = "Major update: new panel, enhanced chat and translations",
        lines = {
            "# Main panel",
            "- New addon status list with icons: loaded, disabled, pending /reload, cannot load or not installed.",
            "- The status is checked for the current character.",
            "- Enable button for installed but disabled addons and Download button for missing ones.",
            "- When closing the window it reminds you to reload the interface if you enabled any addon.",
            "- More compact import buttons below the list.",
            "- Selecting LizeUI in the menu expands all of its sections.",
            "",
            "# Utilities",
            "- New Enhanced chat section:",
            "- Hide guild login messages in chat.",
            "- Disable the game's guild alert, including its sound.",
            "- Guild message sound.",
            "- Whisper notification sound (enabled by default).",
            "- Sound alert when your chosen words appear in chat, comma separated.",
            "- Sounds are picked from a dropdown with the LizeUI sounds first and an icon to preview them without closing it.",
            "- Tooltip: new \"Net -deposit\" line under the Auctionator price. It subtracts the 1 silver deposit and, for stackable items, multiplies by the stack units. If it doesn't cover the deposit, the lost money is shown in red. Enabled by default.",
            "- Automation organized in groups: Vendor, Loot and Group.",
            "- New WOW Beta Interfaces section with the option to remove the Issue Report button.",
            "- The panel now scrolls so every option fits.",
            "",
            "# DarkMode",
            "- New section with the buff/debuff borders, Dark Mode and its intensity.",
            "- You can pick each BetterBlizzFrames Dark Mode section: unit frames, action bars, castbars, auras, minimap, tooltip, elite texture, objectives and nameplate resource.",
            "- If BetterBlizzFrames is not loaded, the section is locked with a notice.",
            "",
            "# RXP Navigation",
            "- If RXPGuides is not loaded, the options are locked with a notice.",
            "",
            "# Install window",
            "- Opens the first time each character logs in (before it was only once per account).",
            "- Shows the same addon list as the main panel and locks imports for addons that are not loaded.",
            "- New LizeUI logo.",
            "",
            "# Languages and commands",
            "- Full interface in Spanish and English. It is picked automatically from the client language (Spanish from Spain or Latin America; any other language uses English).",
            "- /lui opens the options, /lui help lists the commands, /lui install opens the install window, /lui load_en and /lui load_es switch the language.",
            "",
            "# Other",
            "- New Changes and Support sections.",
            "- What's new window and chat notice after updating (the window can be disabled).",
            "- Welcome message on login with a reminder of /lui help.",
            "- New LizeUI sounds registered in SharedMedia; the old sounds have been removed.",
            "- BetterBlizzFrames is no longer required. All addons are now optional.",
            "- Auctionator added as an optional addon.",
            "- Removed the DialogueUI camera option.",
        },
    },
    {
        version = "1.5.0",
        date = "11/07/2026",
        title = "RXPGuides navigation route and Utilities",
        lines = {
            "# Navigation route",
            "- Draws the RXPGuides route in gray on the minimap and the world map: current objective, remaining waypoints and next steps (fainter).",
            "- Optional animated direction arrows and smoothed curves that go through every waypoint.",
            "- Works with round or square minimaps, the rotating minimap and OpenMap.",
            "- Options for thickness, opacity, gray tone and number of next steps. Shortcut: /lui ruta.",
            "",
            "# Utilities",
            "- Enhanced tooltip: class color, level by difficulty, guild ranks, unit target, cursor anchor and scale.",
            "- Automation: repair, sell junk, invite from whispers, accept party from friends and faster loot.",
            "",
            "# Other",
            "- Fixed the Details title bar that sometimes appeared blank.",
            "- Updated profiles.",
        },
    },
    {
        version = "1.1.2",
        date = "11/05/2026",
        title = "Updated profiles",
        lines = {
            "- Updated the BetterBlizzFrames and BetterBlizzPlates profiles.",
        },
    },
    {
        version = "1.1.1",
        date = "10/16/2026",
        title = "Updated profiles",
        lines = {
            "- Updated the BetterBlizzFrames profile.",
        },
    },
    {
        version = "1.1.0",
        date = "09/26/2026",
        title = "Dark Mode",
        lines = {
            "- Option to enable the BetterBlizzFrames Dark Mode from LizeUI.",
            "- New control to adjust the Dark Mode intensity.",
        },
    },
    {
        version = "1.0.1",
        date = "09/25/2026",
        title = "Fixes",
        lines = {
            "- Fixed the border that appeared when entering combat.",
            "- Updated the BetterBlizzPlates profile.",
        },
    },
    {
        version = "1.0.0",
        date = "09/25/2026",
        title = "First release of LizeUI Forever",
        lines = {
            "- Custom menu with the WoW Forever interface style.",
            "- LizeUI added to Options > AddOns.",
            "- Addon check and support submenus.",
            "- Buttons to import the BetterBlizzPlates and BetterBlizzFrames profiles.",
            "- Editable buff/debuff and target borders (custom icons remove the classic border).",
            "- Option to remove the Issue Report button.",
            "- Rotation angle for the DialogueUI zoom.",
        },
    },
}
