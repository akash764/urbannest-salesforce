public with sharing class WhatsAppNotificationService {

    /**
     * Sends WhatsApp message alert using WhatsApp Business Cloud API / Provider
     */
    @future(callout=true)
    public static void sendPaymentLinkAlert(String phone, String customerName, Decimal amount, String paymentType, String linkUrl) {
        String messageBody = 'Dear ' + customerName + ',\n\n' +
                             'Your payment link for ' + paymentType + ' (INR ' + amount + ') at UrbanNest is ready:\n' +
                             linkUrl + '\n\n' +
                             'Please complete the payment before link expiration. Thank you!';
        dispatchWhatsAppMessage(phone, messageBody);
    }

    @future(callout=true)
    public static void sendAppointmentConfirmationAlert(String phone, String customerName, String projectName, String visitDateTime, String driverInfo) {
        String messageBody = 'Dear ' + customerName + ',\n\n' +
                             'Your site visit to UrbanNest ' + projectName + ' is scheduled for ' + visitDateTime + '.\n' +
                             (String.isNotBlank(driverInfo) ? ('Vehicle Details: ' + driverInfo + '\n\n') : '\n') +
                             'Our executive will assist you during the visit. We look forward to welcoming you!';
        dispatchWhatsAppMessage(phone, messageBody);
    }

    @future(callout=true)
    public static void sendPaymentConfirmationAlert(String phone, String customerName, Decimal amount, String paymentType, String receiptNo) {
        String messageBody = 'Dear ' + customerName + ',\n\n' +
                             'We have successfully received your ' + paymentType + ' payment of INR ' + amount + '.\n' +
                             'Transaction Ref: ' + receiptNo + '\n\n' +
                             'Thank you for choosing UrbanNest Real Estate!';
        dispatchWhatsAppMessage(phone, messageBody);
    }

    private static void dispatchWhatsAppMessage(String recipientPhone, String messageText) {
        if (String.isBlank(recipientPhone)) return;

        try {
            HttpRequest req = new HttpRequest();
            // In Production, configure Named Credential for WhatsApp Business API
            req.setEndpoint('callout:WhatsApp_Business_API/v1/messages');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');

            Map<String, Object> payload = new Map<String, Object>{
                'messaging_product' => 'whatsapp',
                'to' => sanitizePhone(recipientPhone),
                'type' => 'text',
                'text' => new Map<String, Object>{ 'body' => messageText }
            };
            req.setBody(JSON.serialize(payload));

            if (!Test.isRunningTest()) {
                Http http = new Http();
                http.send(req);
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'WhatsApp Dispatch failed: ' + ex.getMessage());
        }
    }

    private static String sanitizePhone(String phone) {
        if (phone == null) return '';
        String clean = phone.replaceAll('[^0-9]', '');
        if (clean.length() == 10) {
            clean = '91' + clean; // Default to India country code
        }
        return clean;
    }
}
