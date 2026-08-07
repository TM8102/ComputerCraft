return {
    -- =====================================================
    -- CENTRAL SPAWNER CONFIGURATION
    --
    -- Edit this one file in GitHub instead of editing each
    -- remote spawner computer.
    --
    -- Every remote node uses its own ComputerCraft ID and
    -- loads computers[ID]. If that ID is not listed yet, the
    -- default profile is used.
    -- =====================================================

    configUpdateInterval = 300,
    statusUpdateInterval = 4,

    default = {
        spawners = {
            {
                key = "slot_1",
                name = "N/A",
                outputSide = "front",
                enabled = true
            },
            {
                key = "slot_2",
                name = "N/A",
                outputSide = "back",
                enabled = true
            },
            {
                key = "slot_3",
                name = "N/A",
                outputSide = "left",
                enabled = true
            },
            {
                key = "slot_4",
                name = "N/A",
                outputSide = "right",
                enabled = true
            }
        }
    },

    computers = {
        -- =================================================
        -- EXAMPLE
        --
        -- Replace 123 with the ComputerCraft ID of a remote
        -- spawner computer, then customize only this file.
        --
        -- [123] = {
        --     spawners = {
        --         {
        --             key = "zombie",
        --             name = "Zombie",
        --             outputSide = "front",
        --             enabled = true
        --         },
        --         {
        --             key = "skeleton",
        --             name = "Skeleton",
        --             outputSide = "back",
        --             enabled = true
        --         }
        --     }
        -- },
        -- =================================================
    }
}
