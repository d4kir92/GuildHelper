# GuildHelper

GuildHelper gives your guild its own window with a dashboard, an extended member list, a guild group finder, guild members on the world map, and quick guild invites from chat.

Many features share data between guild members who also use GuildHelper (item level, professions, specs, main character). Members without the addon are still listed with all data the game provides.

## Features

### Dashboard

- Message of the day and guild information.
- Guild statistics: members online / total, members with GuildHelper, average item level of online members.
- "Who is where": online members grouped by zone. Click a name to open the member in the member list.
- Guild news.
- "My guild card": your rank, your public note and, with the right to see it, your officer note.
- Guild professions: how many members have each profession and the best skill level.

### Members

- Searchable and sortable member list with level, main and secondary spec, zone, rank, item level, last seen, public note and officer note.
- Filters for class, rank, online only and hide alts. The filters are remembered.
- Main and alt detection: from the main character set in GuildHelper, or from guild notes that contain another member's name.
- Detail panel with notes, specs, professions, alts or main, and buttons to whisper or invite the member.
- The columns adapt to the window size.
- Classic flavors: a layer column shows the layer of online members who use GuildHelper. Green means the same layer as you. The layer is read from nearby creatures (target, mouseover, nameplates), so it appears once you have seen an NPC.

### Professions and crafting orders

- Find guild crafters by profession or by recipe, and see the materials a recipe needs.
- Each recipe shows the skill level it is learned at.
- Shift+click a recipe, its result or a material to link it in chat while the chat input is open.
- Guild crafting orders: choose a crafter, note which materials you already have, and choose mail or trade for the handover. Open orders are shared with the guild, and you are notified about them.

### Group finder

- **Live:** post a group for a dungeon or raid. The open tank, healer and damage slots are calculated from your current group and update automatically. The post closes when the group is full.
- **Planned:** schedule a group up to two weeks ahead with day, time and slot counts. Planned groups stay visible to the guild while you are offline.
- Guild members apply with their role directly from the list.
- Optional note for every group.
- **Guild chat posts:** publishing a group also posts it to guild chat, in a language you choose. The buttons say what they do: "Publish & post to guild", "Update & post to guild" after a change, or "Post to guild" to post the same group again.
- **Automatic repost:** the guild leader can turn on automatic reposting of live groups for the whole guild (repeat every 2 to 20 minutes). When it is off, the group finder says so and you post again with the button.
- Groups are never posted to guild chat while the game blocks addon chat messages (for example during boss encounters). They are posted once it is allowed again.

### World map

- Shows guild members who use GuildHelper on the world map.
- Members on a flight are shown with their faction icon.
- Tooltip with name, level, rank and flight status.
- Optional level and name labels on the pins.

### Guild invites from chat

- The word `ginv` in chat becomes a clickable link: left or right click invites the sender to your guild.
- Optional keyword: when someone writes `ginv <your word>`, a popup asks whether you want to invite them.

### Character

- Choose your main character once per account and guild. All your alts are then linked to it automatically.
- Set role and spec for your main and secondary spec.
- Optional Twitch name, shown in your member details.

### Designs and languages

- Four designs, switchable live: Material Dark (default), Material Light, Obsidian, and Forever (native WoW window style).
- Choose the addon language independently from the game language.
- Resizable window: drag the grip in the bottom-right corner to resize, Shift+drag to scale, right-click to reset.

## Supported clients

- Retail
- Mists of Pandaria Classic
- Cataclysm Classic
- Wrath of the Lich King Classic / Titan
- The Burning Crusade Classic
- Classic Era
- WoW Forever

## Installation

1. Copy the `GuildHelper` folder into your World of Warcraft `Interface/AddOns` directory.
2. Enable **GuildHelper** in the character-selection add-on list.
3. Log in or reload the user interface.

## Usage

Enter `/guildhelper` or `/guhe` in chat, or left-click the minimap button, to open the window. Right-click the minimap button to hide it.

Language, design, world map options, guild invite options and your character settings are on the **Settings** page of the window.

## Notes

- Addons cannot change guild notes or the message of the day. The edit links in GuildHelper open the Blizzard guild window, where you can change them yourself.
- Item level, professions, specs and main characters are only shown for members who also use GuildHelper.

## Localization

GuildHelper includes translations for all World of Warcraft client locales:

`deDE`, `enUS`, `esES`, `esMX`, `frFR`, `itIT`, `koKR`, `ptBR`, `ruRU`, `zhCN`, and `zhTW`.

## Credits

- The skill level a recipe is learned at ("Learned at") comes from [Wowhead](https://www.wowhead.com/) profession data.

## License

All Rights Reserved, see `LICENSE`.

## Author

D4KiR
