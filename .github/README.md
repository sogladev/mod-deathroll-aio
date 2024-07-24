# Module Deathroll

This is a module compatible for [AzerothCore](http://www.azerothcore.org), [ElunaTrinityWotlk](https://github.com/ElunaLuaEngine/ElunaTrinityWotlk) that implements Deathroll with ElunaLUA and AIO

## Features
- challenge other player to a deathroll
- set bet in gold
- set start roll
- mode to roll to the death
- no need to be grouped
- timeout after a set amount, refund players or award winner
- database persistence
- automatically awards winning player, if winnings are too large then gold is send through ingame mail

ui:

![deathroll_ui](https://github.com/user-attachments/assets/1fbe1299-3366-45fc-87c5-6b194272fa46)


to the death example: 

https://github.com/user-attachments/assets/50a748df-52c2-429a-90e5-02596d377733


challenge and to the death example: https://www.youtube.com/watch?v=2YXcdoI8CQ0

## Configuration
removeGoldAtStart: enable to take gold from players upon start of the game
enableDB: enable database persistence, if removeGoldAtStart is enabled, on restart will refund games that were still in progress
customize strings
allowToTheDeath: enable/hide skull button
set timeouts: how much time is allowed between rolls 

## Tested with
AzerothCore
ElunaTrinityWotlk

## How to play:
- `.dr` to open the window
- `.dra` to accept a challenge
- `.drd` to decline a challenge, challenge can automatically timeout and decline

Target another player and click "Challenge" or the "Skull". Skull will do "Challenge" and kill the losing player

## Requirements
AIO https://github.com/Rochet2/AIO/tree/master

## Database
If config enabled, requires a table `deathroll`. This table will be auto generated on launch.

These will be auto-executed on launch with `ac_eluna` changes based on your config

Recorded data

stores completed and in progress deathrolls
```
|id|challengerGUID|targetGUID|wager|status|time|
|--|--------------|----------|-----|------|----|
|1|94|70|10000|3|2024-07-24 21:37:43|
```

## License

[LICENSE](./../LICENSE)

## How to create your own module

1. Use the script `create_module.sh` located in [`modules/`](https://github.com/azerothcore/azerothcore-wotlk/tree/master/modules) to start quickly with all the files you need and your git repo configured correctly (heavily recommended).
1. You can then use these scripts to start your project: https://github.com/azerothcore/azerothcore-boilerplates
1. Do not hesitate to compare with some of our newer/bigger/famous modules.
1. Edit the `README.md` and other files (`include.sh` etc...) to fit your module. Note: the README is automatically created from `README_example.md` when you use the script `create_module.sh`.
1. Publish your module to our [catalogue](https://github.com/azerothcore/modules-catalogue).
