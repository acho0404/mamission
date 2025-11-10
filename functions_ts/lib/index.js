"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.stripeWebhook = exports.createPaymentIntent = void 0;
const functions = require("firebase-functions/v2");
const https_1 = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const stripe_1 = require("stripe");
admin.initializeApp();
const stripe = new stripe_1.default(process.env.STRIPE_SECRET_KEY, {
    apiVersion: "2024-06-20",
});
// createPaymentIntent callable
exports.createPaymentIntent = (0, https_1.onCall)({ region: "us-central1", memory: "512MiB", timeoutSeconds: 60 }, async (request) => {
    const amount = Number(request.data.amount);
    const currency = (request.data.currency || "eur").toString();
    const description = (request.data.description || "Mission payment").toString();
    if (!amount || amount <= 0) {
        throw new functions.https.HttpsError("invalid-argument", "Montant invalide");
    }
    const intent = await stripe.paymentIntents.create({
        amount,
        currency,
        description,
        automatic_payment_methods: { enabled: true },
    });
    return { clientSecret: intent.client_secret };
});
// stripeWebhook
exports.stripeWebhook = (0, https_1.onRequest)({ region: "us-central1", memory: "512MiB", timeoutSeconds: 60 }, async (req, res) => {
    const sig = req.headers["stripe-signature"];
    const endpointSecret = process.env.STRIPE_WEBHOOK_SECRET;
    let event;
    try {
        event = stripe.webhooks.constructEvent(req.rawBody, sig, endpointSecret);
    }
    catch (err) {
        console.error("⚠️ Signature Stripe invalide :", err.message);
        res.status(400).send(`Webhook Error: ${err.message}`);
        return;
    }
    switch (event.type) {
        case "payment_intent.succeeded":
            console.log("✅ Paiement réussi :", event.data.object["id"]);
            break;
        case "payment_intent.payment_failed":
            console.log("❌ Paiement échoué :", event.data.object["id"]);
            break;
        default:
            console.log("ℹ️ Événement Stripe :", event.type);
    }
    res.json({ received: true });
});
