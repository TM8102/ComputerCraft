return {
    -- =====================================================
    -- EXAMPLE 1
    -- Iron is stored in the Functional Storage system.
    --
    -- Target = 20,000
    --
    -- Below 50% of target:
    -- below 10,000 -> machine ON
    --
    -- At 100%:
    -- 20,000 -> machine OFF
    -- =====================================================

    ["industrialforegoing:ether_gas"] = {
        displayName = "Ether Gas",
        target = 512000,

        machine = {
            computerID = 16,
            machineKey = "ether_gas",
            side = "bottom",

            startBelow = 50,
            stopAt = 100
        }
    },
    ["allthemodium:soul_lava"] = {
        displayName = "Soul Lava",
        target = 512000,

        machine = {
            computerID = 16,
            machineKey = "soul_lava",
            side = "top",

            startBelow = 50,
            stopAt = 100
        }
    },
    ["industrialforegoing:pink_slime"] = {
        displayName = "Pink Slime",
        target = 512000,

        machine = {
            computerID = 12,
            machineKey = "pink_slime",
            side = "top",

            startBelow = 50,
            stopAt = 100
        }
    },
    ["mysticalagriculture:dye_essence"] = {
        displayName = "Dye Essence",
        target = 65500,

        machine = {
            computerID = 4,
            machineKey = "dye_essence",
            side = "right",

            startBelow = 50,
            stopAt = 100
        }
    },
    ["mysticalagriculture:dragon_egg_essence"] = {
        displayName = "Dragon Egg Essence",
        target = 65500,

        machine = {
            computerID = 4,
            machineKey = "dragon_essence",
            side = "back",

            startBelow = 50,
            stopAt = 100
        }
    },
    ["mysticalagriculture:soulium_essence"] = {
        displayName = "Soulium Essence",
        target = 65500,

        machine = {
            computerID = 4,
            machineKey = "solium_essence",
            side = "left",

            startBelow = 50,
            stopAt = 100
        }
    },
    ["mysticalagradditions:insanium_essence"] = {
        displayName = "Insanium Essence",
        target = 65500,

        machine = {
            computerID = 4,
            machineKey = "insanium_essence",
            side = "front",

            startBelow = 50,
            stopAt = 100
        }
    },
    ["minecraft:nether_star"] = {
        displayName = "Nether Star",
        target = 65500,

        machine = {
            computerID = 34,
            machineKey = "nether_star",
            side = "right",

            startBelow = 50,
            stopAt = 100
        }
    },
    ["industrialforegoing:meat"] = {
        displayName = "Liquid Meat",
        target = 32000,

        machine = nil
        
    },
    ["mysticalagriculture:fertilized_essence"] = {
        displayName = "Fertilized Essence",
        target = 65500,

        machine = nil
    }
}