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
        target = 67108864,

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
        target = 67108864,

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
        target = 67108864,

        machine = {
            computerID = 4,
            machineKey = "solium_essence",
            side = "left",

            startBelow = 50,
            stopAt = 100
        }
    },
    ["mysticalagriculture:nature_essence"] = {
        displayName = "Nature Essence",
        target = 67108864,

        machine = {
            computerID = 34,
            machineKey = "nature_essence",
            side = "back",

            startBelow = 50,
            stopAt = 100
        }
    },
    ["mysticalagriculture:nether_essence"] = {
        displayName = "Nether Essence",
        target = 67108864,

        machine = {
            computerID = 34,
            machineKey = "nether_essence",
            side = "left",

            startBelow = 50,
            stopAt = 100
        }
    },
    ["mysticalagriculture:sculk_essence"] = {
        displayName = "Sculk Essence",
        target = 67108864,

        machine = {
            computerID = 34,
            machineKey = "skulk_essence",
            side = "front",

            startBelow = 50,
            stopAt = 100
        }
    },
    ["mysticalagriculture:dirt_essence"] = {
        displayName = "Dirt Essence",
        target = 67108864,

        machine = {
            computerID = 35,
            machineKey = "dirt_essence",
            side = "back",

            startBelow = 50,
            stopAt = 100
        }
    },
    ["mysticalagriculture:water_essence"] = {
        displayName = "Water Essence",
        target = 67108864,

        machine = {
            computerID = 35,
            machineKey = "water_essence",
            side = "right",

            startBelow = 50,
            stopAt = 100
        }
    },
    ["mysticalagriculture:honey_essence"] = {
        displayName = "Honey Essence",
        target = 67108864,

        machine = {
            computerID = 35,
            machineKey = "honey_essence",
            side = "left",

            startBelow = 50,
            stopAt = 100
        }
    },
    ["mysticalagriculture:stone_essence"] = {
        displayName = "Stone Essence",
        target = 67108864,

        machine = {
            computerID = 35,
            machineKey = "stone_essence",
            side = "front",

            startBelow = 50,
            stopAt = 100
        }
    },
    ["mysticalagriculture:fire_essence"] = {
        displayName = "Fire Essence",
        target = 67108864,

        machine = {
            computerID = 11,
            machineKey = "fire_essence",
            side = "back",

            startBelow = 50,
            stopAt = 100
        }
    },
    ["mysticalagradditions:insanium_essence"] = {
        displayName = "Insanium",
        target = 67108864,

        machine = {
            computerID = 4,
            machineKey = "insanium_essence",
            side = "front",

            startBelow = 50,
            stopAt = 100
        }
    },
    ["mysticalagriculture:experience_essence"] = {
        displayName = "Experience Essence",
        target = 67108864,

        machine = {
            computerID = 11,
            machineKey = "experience_essence",
            side = "left",

            startBelow = 50,
            stopAt = 100
        }
    },
    ["mysticalagriculture:deepslate_essence"] = {
        displayName = "Deepslate Essence",
        target = 67108864,

        machine = {
            computerID = 11,
            machineKey = "deepslate_essence",
            side = "front",

            startBelow = 50,
            stopAt = 100
        }
    },
    ["minecraft:nether_star"] = {
        displayName = "Nether Star",
        target = 67108864,

        machine = {
            computerID = 34,
            machineKey = "nether_star",
            side = "right",

            startBelow = 50,
            stopAt = 100
        }
    },
    ["justdirethings:time_fluid_source"] = {
        displayName = "Time Fluid",
        target = 2097152000,

        machine = {
            computerID = 32,
            machineKey = "time_fluid",
            side = "front",

            startBelow = 50,
            stopAt = 100
        }
    },
    ["minecraft:iron_ingot"] = {
        displayName = "Iron Ingot",
        target = 2097152000,

        machine = {
            computerID = 500,
            machineKey = "iron_ingot",
            side = "front",

            startBelow = 50,
            stopAt = 100
        }
    },
    ["minecraft:gold_ingot"] = {
        displayName = "Gold Ingot",
        target = 2097152000,

        machine = {
            computerID = 500,
            machineKey = "gold_ingot",
            side = "right",

            startBelow = 50,
            stopAt = 100
        }
    },
    ["allthemodium:allthemodium_ingot"] = {
        displayName = "AllTheModium Ingot",
        target = 67108864,
        machine = nil
    },
    ["allthemodium:vibranium_ingot"] = {
        displayName = "Vibranium Ingot",
        target = 67108864,
        machine = nil
    },
    ["allthemodium:unobtainium_ingot"] = {
        displayName = "Unobtainium Ingot",
        target = 67108864,
        machine = nil
    },
    ["justdirethings:polymorphic_fluid_source"] = {
        displayName = "Polymorphic Fluid",
        target = 512000,
        machine = nil
    },
    ["industrialforegoing:meat"] = {
        displayName = "Liquid Meat",
        target = 32000,
        machine = nil
        
    },
    ["minecraft:redstone"] = {
        displayName = "Redstone",
        target = 42467328,
        machine = nil
        
    },
    ["minecraft:emerald"] = {
        displayName = "Emeralds",
        target = 4718592,
        machine = nil
        
    },
    ["minecraft:copper_ingot"] = {
        displayName = "Copper Ingots",
        target = 4718592,
        machine = nil
        
    },
    ["alltheores:zinc_ingot"] = {
        displayName = "Zinc Ingots",
        target = 4718592,
        machine = nil
        
    },
    ["alltheores:silver_ingot"] = {
        displayName = "Silver Ingots",
        target = 4718592,
        machine = nil
        
    },
    ["alltheores:lead_ingot"] = {
        displayName = "Lead Ingots",
        target = 4718592,
        machine = nil
        
    },
    ["alltheores:tin_ingot"] = {
        displayName = "Tin Ingots",
        target = 4718592,
        machine = nil
        
    },
    ["alltheores:platinum_ingot"] = {
        displayName = "Platinum Ingots",
        target = 4718592,
        machine = nil
        
    },
    ["powah:uraninite_raw"] = {
        displayName = "Raw Uraninite",
        target = 4718592,
        machine = nil
        
    },
    ["minecraft:diamond"] = {
        displayName = "Diamonds",
        target = 4718592,
        machine = nil
        
    },
    ["minecraft:coal"] = {
        displayName = "Coal",
        target = 1327104,
        machine = nil
        
    },
    ["minecraft:lapis_lazuli"] = {
        displayName = "Lapis",
        target = 1327104,
        machine = nil
        
    },
    ["minecraft:quartz"] = {
        displayName = "Quartz",
        target = 42467328,
        machine = nil
        
    },
    ["ae2:certus_quartz_crystal"] = {
        displayName = "Certus Quartz Crystal",
        target = 150994944,
        machine = nil
        
    },
    ["alltheores:osmium_ingot"] = {
        displayName = "Osmium Ingots",
        target = 4718592,
        machine = nil
        
    },
    ["alltheores:aluminum_ingot"] = {
        displayName = "Aluminum Ingots",
        target = 4718592,
        machine = nil
        
    },
    ["alltheores:uranium_ingot"] = {
        displayName = "Uranium Ingots",
        target = 4718592,
        machine = nil
        
    },
    ["alltheores:nickel_ingot"] = {
        displayName = "Nickel Ingots",
        target = 4718592,
        machine = nil
        
    },
    ["mysticalagriculture:fertilized_essence"] = {
        displayName = "Fertilized Essence",
        target = 67108864,
        machine = nil
    },
    ["justdirethings:polymorphic_catalyst"] = {
        displayName = "Polymorphic Catalyst",
        target = 67108864,
        machine = nil
    },
    ["mysticalagriculture:awakended_draconium_essence"] = {
        displayName = "Awakended Dragonium Essence",
        target = 67108864,
        machine = {
            computerID = 11,
            machineKey = "awakened_draconium_essence",
            side = "right",

            startBelow = 50,
            stopAt = 100
        }
    }
}