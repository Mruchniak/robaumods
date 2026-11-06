local _, ns = ...

-- Word lists used to guess a message's language. Only words that are NOT common
-- in English are listed, to avoid false positives. All lowercase.
local function set(str)
    local t = {}
    for w in str:gmatch("%S+") do t[w] = true end
    return t
end

ns.WORDS = {
    de = set([[
        ich nicht und der das ist ein eine einen bitte suche suchen wir kann kannst mit auf
        fuer für noch jemand gruppe hallo danke aber auch wie habe sind schon nur nein wer zum zur
        dass oder wenn dich mich mir dir gilde heute jetzt kein keine hier dann wann warum
        guten abend morgen tschuess tschüss moin servus mal mehr sehr wirklich brauche brauchen
        heiler ihr euch uns weil gerade gibt gibts vielleicht kommt komm kommen
        lasst wollen will willst muss musst machen geht gehen schnell bisschen ganz alles
        niemand sucht gesucht
    ]]),
    fr = set([[
        je tu il elle nous vous ils est pas les des une pour avec dans sur qui que quoi salut
        bonjour bonsoir merci oui cherche cherchons groupe besoin fait mais tres très bien aussi
        comment pourquoi quelqu quelquun guilde donjon ça ca svp stp ptn mdr slt suis sont
        peut peux veux voulez veut allez vas vais viens venir tout tous toute rien personne
        encore deja déjà alors donc voila voilà moi toi lui mon ton ses mes tes cette ces
        recherche soigneur
    ]]),
    -- Transliterated Russian (latin letters). Real Cyrillic is detected separately.
    ru = set([[
        privet spasibo spasiba pozhaluysta davai davay nuzhen nuzhna nuzhny nado kto poshli
        blyat blya suka pizdec nahui nahuy ischu ishchu zdarova
    ]]),
}

-- Characters that hint at a language (add one hit per message).
ns.MARKERS = {
    de = { "ä", "ö", "ü", "ß", "Ä", "Ö", "Ü" },
    fr = { "é", "è", "ê", "à", "ç", "â", "î", "ô", "û", "ù", "œ", "É", "È", "À" },
}
