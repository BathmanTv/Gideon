--[[--------------------------------------------------------------------------
    tests/fixtures/assignment_sample.lua

    FIXTURE DE CONTRAT : ce fichier contient EXACTEMENT ce que GIDEON ecrit dans
    WTF/Account/<COMPTE>/SavedVariables/GideonRaid.lua (bloc `assignment`).
    Si GIDEON change le format, ce fichier et les tests qui l'utilisent cassent :
    c'est voulu (test de contrat, docs/TESTPLAN.md etape 4).

    `plan` est OPTIONNEL : c'est le plan prepare hors jeu (role / position par
    joueur). Les roles "1" / "2" / "3" sont ceux de la mecanique des orbes.
----------------------------------------------------------------------------]]
return {
    schema = 1,
    pairs = {
        { a = "Bathman", b = "Coren" },
        { a = "Velna", b = "Torgh" },
    },
    plan = {
        { name = "Velna", role = "2", position = "MIDDLE" },
        { name = "Torgh", role = "2", position = "MIDDLE" },
        { name = "Bathman", role = "1", position = "LEFT" },
        { name = "Coren", role = "3", position = "RIGHT" },
    },
}
