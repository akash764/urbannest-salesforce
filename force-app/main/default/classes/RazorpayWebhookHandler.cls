@RestResource(urlMapping='/api/razorpay/webhook/*')
global without sharing class RazorpayWebhookHandler {

    private static final String DEFAULT_WEBHOOK_SECRET = 'YOUR_RAZORPAY_WEBHOOK_SECRET';

    @HttpPost
    global static void handleWebhook() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        String requestBody = req == null || req.requestBody == null ? '' : req.requestBody.toString();
        String signatureHeader = req != null && req.headers != null ? req.headers.get('X-Razorpay-Signature') : null;

        if (String.isBlank(requestBody)) {
            res.statusCode = 400;
            res.responseBody = Blob.valueOf('{"status":"error","message":"Empty request body"}');
            return;
        }

        if (!verifySignature(requestBody, signatureHeader)) {
            res.statusCode = 401;
            res.responseBody = Blob.valueOf('{"status":"error","message":"Invalid signature"}');
            return;
        }

        try {
            Map<String, Object> payloadMap = (Map<String, Object>) JSON.deserializeUntyped(requestBody);
            String eventType = (String) payloadMap.get('event');

            if ('payment_link.paid'.equalsIgnoreCase(eventType) || 'payment.captured'.equalsIgnoreCase(eventType)) {
                processPaymentPaid(payloadMap, requestBody);
            }

            res.statusCode = 200;
            res.responseBody = Blob.valueOf('{"status":"success"}');
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Razorpay Webhook Error: ' + ex.getMessage() + '\n' + ex.getStackTraceString());
            res.statusCode = 500;
            res.responseBody = Blob.valueOf('{"status":"error","message":"' + ex.getMessage() + '"}');
        }
    }

    public static Boolean verifySignature(String payload, String signature) {
        if (String.isBlank(signature)) {
            return false;
        }
        try {
            String webhookSecret = getWebhookSecret();
            Blob hmac = Crypto.generateMac('HmacSHA256', Blob.valueOf(payload), Blob.valueOf(webhookSecret));
            String calculatedSignature = EncodingUtil.convertToHex(hmac);
            return calculatedSignature.equalsIgnoreCase(signature);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Signature verification exception: ' + e.getMessage());
            return false;
        }
    }

    private static String getWebhookSecret() {
        return DEFAULT_WEBHOOK_SECRET;
    }

    private static void processPaymentPaid(Map<String, Object> payloadMap, String rawJson) {
        Map<String, Object> payload = (Map<String, Object>) payloadMap.get('payload');
        if (payload == null) return;

        String paymentLinkId = null;
        String razorpayPaymentId = null;

        if (payload.containsKey('payment_link')) {
            Object paymentLinkObject = payload.get('payment_link');
            if (paymentLinkObject instanceof Map<String, Object>) {
                Map<String, Object> linkMap = (Map<String, Object>) paymentLinkObject;
                Object entityObj = linkMap.get('entity');
                if (entityObj instanceof Map<String, Object>) {
                    Map<String, Object> linkEntity = (Map<String, Object>) entityObj;
                    paymentLinkId = (String) linkEntity.get('id');
                }
            }
        }

        if (payload.containsKey('payment')) {
            Object paymentObject = payload.get('payment');
            if (paymentObject instanceof Map<String, Object>) {
                Map<String, Object> paymentMap = (Map<String, Object>) paymentObject;
                Object entityObj = paymentMap.get('entity');
                if (entityObj instanceof Map<String, Object>) {
                    Map<String, Object> paymentEntity = (Map<String, Object>) entityObj;
                    razorpayPaymentId = (String) paymentEntity.get('id');
                }
            }
        }

        if (String.isBlank(paymentLinkId) && String.isBlank(razorpayPaymentId)) {
            return;
        }

        String paymentQuery = buildPaymentQuery();
        String paymentFilter = ' WHERE ' + buildFieldClause('Razorpay_Payment_Link_Id__c', paymentLinkId, true, true) +
            ' OR ' + buildFieldClause('Razorpay_Payment_Id__c', razorpayPaymentId, true, true);
        String query = paymentQuery + paymentFilter + ' LIMIT 1';

        List<SObject> paymentRows = Database.query(query);
        if (paymentRows.isEmpty()) {
            System.debug(LoggingLevel.WARN, 'No matching Payment__c record found for link: ' + paymentLinkId);
            return;
        }

        SObject paymentRecord = paymentRows[0];
        String paymentType = safeStringValue(paymentRecord, 'Payment_Type__c');
        Id opportunityId = safeIdValue(paymentRecord, 'Opportunity__c');
        Id houseUnitId = null;

        safePut(paymentRecord, 'Payment_Status__c', 'Paid');
        safePut(paymentRecord, 'Paid_Date_Time__c', DateTime.now());
        safePut(paymentRecord, 'Raw_Webhook_Response__c', rawJson.length() > 32000 ? rawJson.substring(0, 32000) : rawJson);
        if (String.isNotBlank(razorpayPaymentId)) {
            safePut(paymentRecord, 'Razorpay_Payment_Id__c', razorpayPaymentId);
        }
        update paymentRecord;

        recalculateOpportunityAndHouse(opportunityId, paymentType, houseUnitId);
    }

    public static void recalculateOpportunityAndHouse(Id oppId, String paymentType, Id houseUnitId) {
        if (oppId == null) return;

        String paymentQuery = 'SELECT Id, Amount__c, Payment_Type__c, Payment_Status__c, Opportunity__c FROM Payment__c WHERE Opportunity__c = \'' + String.escapeSingleQuotes(String.valueOf(oppId)) + '\' AND Payment_Status__c = \'Paid\'';
        List<SObject> paidPayments = Database.query(paymentQuery);

        Decimal totalAdvance = 0;
        Decimal totalSettled = 0;
        for (SObject paymentRecord : paidPayments) {
            String paymentKind = safeStringValue(paymentRecord, 'Payment_Type__c');
            Decimal amount = safeDecimalValue(paymentRecord, 'Amount__c');
            if ('Advance'.equalsIgnoreCase(paymentKind)) {
                totalAdvance += amount == null ? 0 : amount;
            } else if ('Settlement'.equalsIgnoreCase(paymentKind)) {
                totalSettled += amount == null ? 0 : amount;
            }
        }

        String oppQuery = 'SELECT Id, StageName, Projected_Amount__c, Advance_Paid__c, Settled_Amount__c, House_Unit__c FROM Opportunity WHERE Id = \'' + String.escapeSingleQuotes(String.valueOf(oppId)) + '\' LIMIT 1';
        List<SObject> oppRows = Database.query(oppQuery);
        if (oppRows.isEmpty()) return;

        SObject opportunityRecord = oppRows[0];
        Decimal projectedAmount = safeDecimalValue(opportunityRecord, 'Projected_Amount__c');
        Decimal existingAdvancePaid = safeDecimalValue(opportunityRecord, 'Advance_Paid__c');
        Decimal existingSettled = safeDecimalValue(opportunityRecord, 'Settled_Amount__c');
        String currentStage = safeStringValue(opportunityRecord, 'StageName');
        Id targetHouseId = safeIdValue(opportunityRecord, 'House_Unit__c');
        if (targetHouseId == null) {
            targetHouseId = houseUnitId;
        }

        safePut(opportunityRecord, 'Advance_Paid__c', totalAdvance);
        safePut(opportunityRecord, 'Settled_Amount__c', totalSettled);

        SObject houseToUpdate = null;
        if ('Advance'.equalsIgnoreCase(paymentType) && totalAdvance > 0) {
            if ('Advance Payment'.equalsIgnoreCase(currentStage)) {
                safePut(opportunityRecord, 'StageName', 'Document Collection');
            }
            if (targetHouseId != null) {
                houseToUpdate = createHouseUnitRecord(targetHouseId, 'Reserved');
            }
        }

        if (totalSettled > 0 && projectedAmount != null && (totalAdvance + totalSettled) >= projectedAmount) {
            if (!'Key Handover'.equalsIgnoreCase(currentStage)) {
                safePut(opportunityRecord, 'StageName', 'Construction Milestone');
            }
            if (targetHouseId != null) {
                houseToUpdate = createHouseUnitRecord(targetHouseId, 'Sold');
            }
        }

        update opportunityRecord;
        if (houseToUpdate != null) {
            update houseToUpdate;
        }
    }

    private static String buildPaymentQuery() {
        List<String> fields = new List<String>{
            'Id',
            'Opportunity__c',
            'Payment_Type__c',
            'Payment_Status__c',
            'Amount__c',
            'Razorpay_Payment_Link_Id__c',
            'Razorpay_Payment_Id__c'
        };
        return 'SELECT ' + String.join(fields, ', ') + ' FROM Payment__c';
    }

    private static String buildFieldClause(String fieldName, String value, Boolean includeIsNotNull, Boolean isStringValue) {
        if (String.isBlank(value) && includeIsNotNull) {
            return fieldName + ' != null';
        }
        if (isStringValue) {
            return fieldName + ' = \'' + String.escapeSingleQuotes(value) + '\'';
        }
        return fieldName + ' = ' + value;
    }

    private static SObject createHouseUnitRecord(Id houseId, String statusValue) {
        Schema.SObjectType houseType = Schema.getGlobalDescribe().get('House_Unit__c');
        if (houseType == null) return null;
        SObject houseRecord = houseType.newSObject();
        safePut(houseRecord, 'Id', houseId);
        safePut(houseRecord, 'Status__c', statusValue);
        return houseRecord;
    }

    private static void safePut(SObject record, String fieldApiName, Object value) {
        if (record == null || String.isBlank(fieldApiName)) return;
        Schema.DescribeSObjectResult describeResult = record.getSObjectType().getDescribe();
        if (describeResult.fields.getMap().containsKey(fieldApiName)) {
            record.put(fieldApiName, value);
        }
    }

    private static String safeStringValue(SObject record, String fieldApiName) {
        if (record == null || String.isBlank(fieldApiName)) return null;
        return record.getSObjectType().getDescribe().fields.getMap().containsKey(fieldApiName)
            ? String.valueOf(record.get(fieldApiName))
            : null;
    }

    private static Id safeIdValue(SObject record, String fieldApiName) {
        if (record == null || String.isBlank(fieldApiName)) return null;
        return record.getSObjectType().getDescribe().fields.getMap().containsKey(fieldApiName)
            ? (Id) record.get(fieldApiName)
            : null;
    }

    private static Decimal safeDecimalValue(SObject record, String fieldApiName) {
        if (record == null || String.isBlank(fieldApiName)) return null;
        if (!record.getSObjectType().getDescribe().fields.getMap().containsKey(fieldApiName)) {
            return null;
        }
        Object value = record.get(fieldApiName);
        return value == null ? null : (Decimal) value;
    }
}
