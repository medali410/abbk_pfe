const n8nWebhookUrl = 'http://localhost:5678/webhook-test/ai-motor-analysis';

const testData = {
    machineId: "TEST_AI_MANUAL",
    metrics: {
        thermal: 95,
        power: 65,
        pressure: 12000
    },
    timestamp: Date.now().toString()
};

console.log("Sending test data to n8n...");

fetch(n8nWebhookUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(testData)
})
    .then(res => {
        console.log("Response status:", res.status);
        return res.text();
    })
    .then(text => console.log("Response body:", text))
    .catch(err => console.error("Error calling n8n:", err.message));
