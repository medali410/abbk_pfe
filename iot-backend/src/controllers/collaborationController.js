/**
 * Collaboration Controller
 * Handles data for the technician team collaboration & maintenance operations
 */

exports.getCollaborationData = async (req, res) => {
    try {
        const collaborationData = {
            stats: {
                activeUnits: 14,
                queuedRequests: 8,
                latency: "4.2m",
                successProtocols: 128
            },
            operations: [
                {
                    id: "8829-X",
                    name: "Marcus Thorne",
                    role: "L3 STRUCTURAL LEAD",
                    task: "Core Cooling Bypass",
                    location: "Vault_7 / Sub-Level B",
                    progress: 0.75,
                    imageUrl: "https://i.pravatar.cc/150?u=m1"
                },
                {
                    id: "4102-Y",
                    name: "Elena Vance",
                    role: "NETWORK ARCHITECT",
                    task: "Fiber Uplink Repair",
                    location: "Comm_Tower_Alpha",
                    progress: 0.25,
                    imageUrl: "https://i.pravatar.cc/150?u=m2"
                },
                {
                    id: "9912-A",
                    name: "Jaxon Kael",
                    role: "CYBER ANALYST",
                    task: "Firewall Integration",
                    location: "Data_Center_Central",
                    progress: 0.0,
                    imageUrl: "https://i.pravatar.cc/150?u=m3"
                },
                {
                    id: "1004-B",
                    name: "Sarah Chen",
                    role: "HVAC SPECIALIST",
                    task: "Condenser Scrubbing",
                    location: "Sector_9 / Roof",
                    progress: 0.9,
                    imageUrl: "https://i.pravatar.cc/150?u=m4"
                }
            ],
            chatMessages: [
                {
                    user: "MARCUS THORNE",
                    time: "10:42:01",
                    text: "Cooling bypass completed. Pressure returning to nominal levels in Vault_7.",
                    active: true
                },
                {
                    user: "ELENA VANCE",
                    time: "10:45:15",
                    text: "Experiencing interference on the Tower Alpha uplink. Requesting secondary signal scan.",
                    active: true
                },
                {
                    user: "SYS_ADMIN",
                    time: "11:00:00",
                    text: "Protocol G-12 initialized. All technicians must report status update in 5min.",
                    active: true,
                    system: true
                }
            ]
        };

        res.status(200).json(collaborationData);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
};
