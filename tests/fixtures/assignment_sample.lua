--[[--------------------------------------------------------------------------
    tests/fixtures/assignment_sample.lua

    FIXTURE DE CONTRAT : ce fichier contient EXACTEMENT ce que GIDEON ecrit dans
    WTF/Account/<COMPTE>/SavedVariables/GideonRaid.lua (bloc `assignment`).
    Si GIDEON change le format, ce fichier et les tests qui l'utilisent cassent :
    c'est voulu (test de contrat, docs/TESTPLAN.md etape 4).

    `plan` est OPTIONNEL : c'est le plan prepare hors jeu (role / position par
    joueur). Le `role` porte la COMPOSITION D'ORBES (« 1V3R », « 2V2R », « 3V1R ») :
    les numeros 1/3 sont AMBIGUS sur les couleurs, seul « 2 » ne l'est pas.
----------------------------------------------------------------------------]]
--
return {
    schema = 1,
    pairs = {
        { a = "Bathman", b = "Coren" },
        { a = "Velna", b = "Torgh" },
    },
    plan = {
        { name = "Velna", role = "2V2R", position = "MIDDLE" },
        { name = "Torgh", role = "2V2R", position = "MIDDLE" },
        { name = "Bathman", role = "1V3R", position = "HOLD" },
        { name = "Coren", role = "3V1R", position = "PURSUE" },
    },
}
