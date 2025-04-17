const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

module.exports = buildModule("RagnarokGameDeployment", (m: any) => {
    // Get timestamp as version to ensure uniqueness
    const timestamp = Math.floor(Date.now() / 1000);
    const versionId = `v${timestamp}`;
    
    // Deploy core contracts with versioned names
    const ragnarok = m.contract("Ragnarok", [], {
        id: `Ragnarok${versionId}`
    });
    
    const gameMaster = m.contract("GameMaster", [], {
        id: `GameMaster${versionId}`
    });
    
    const doors = m.contract("Doors", [], {
        id: `Doors${versionId}`
    });

    // Setup contract relationships with versioned IDs
    const setupGameMaster = m.call(gameMaster, "registerGame", ["Doors", doors], {
        id: `setup_game_master${versionId}`
    });

    const setupDoors = m.call(doors, "setGameMaster", [gameMaster], {
        id: `setup_doors${versionId}`,
        after: [setupGameMaster]
    });

    const setupRagnarok = m.call(gameMaster, "setRagnarokAddress", [ragnarok], {
        id: `setup_ragnarok${versionId}`,
        after: [setupDoors]
    });

    // Return all deployed contracts
    return {
        ragnarok,
        gameMaster,
        doors,
        setupSteps: {
            setupGameMaster,
            setupDoors,
            setupRagnarok
        }
    };
});
