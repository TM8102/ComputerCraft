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

    ["minecraft:iron_ingot"] = {
        displayName = "Iron",
        target = 20000,

        machine = {
            computerID = 0,
            machineKey = "iron",
            side = "top",

            startBelow = 50,
            stopAt = 100
        }
    },
    ["minecraft:gold_ingot"] = {
        displayName = "Gold",
        target = 12000,

        machine = {
            computerID = 0,
            machineKey = "gold",
            side = "bottom",

            startBelow = 50,
            stopAt = 100
        }
    },
    ["minecraft:redstone"] = {
        displayName = "Redstone",
        target = 50000,

        machine = {
            computerID = 0,
            machineKey = "redstone",
            side = "left",

            startBelow = 50,
            stopAt = 100
        }
    },
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
    ["minecraft:diamond"] = {
        displayName = "Diamond",
        target = 512000,

        machine = {
            computerID = 202,
            machineKey = "diamond",
            side = "top",

            startBelow = 50,
            stopAt = 100
        }
    },
    ["mysticalagriculture:dye_essence"] = {
        displayName = "Dye Essence",
        target = 512000,

        machine = {
            computerID = 202,
            machineKey = "dye_essence",
            side = "back",

            startBelow = 50,
            stopAt = 100
        }
    },
    ["industrialforegoing:meat"] = {
        displayName = "Liquid Meat",
        target = 32000,
        
        machine = nil
        
    },

    -- =====================================================
    -- STORAGE ONLY
    --
    -- This appears on the Main Storage screen but does NOT
    -- automatically control any machine.
    -- =====================================================

    ["minecraft:dirt"] = {
        displayName = "Dirt",
        target = 10000,

        machine = nil
    }
}