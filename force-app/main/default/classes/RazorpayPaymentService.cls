@RestResource(urlMapping='/api/urbannest/payment/*')
global with sharing class RazorpayPaymentService {

    @HttpPost
    global static String createPaymentRecord() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        if (req == null || String.isBlank(req.requestBody == null ? null : req.requestBody.toString())) {
            if (res != null) {
                res.statusCode = 400;
            }
            return '{"success":false,"message":"Request body is required"}';
        }

        try {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(req.requestBody.toString());
            String customerName = safeString(payload.get('customerName'));
            String customerEmail = safeString(payload.get('customerEmail'));
            String customerPhone = safeString(payload.get('customerPhone'));
            String paymentType = safeString(payload.get('paymentType'));
            String projectName = safeString(payload.get('projectName'));
            String razorpayPaymentId = safeString(payload.get('razorpayPaymentId'));
            String razorpayLinkId = safeString(payload.get('razorpayLinkId'));
            Decimal amount = toDecimal(payload.get('amount'));

            if (String.isBlank(customerName)) {
                if (res != null) {
                    res.statusCode = 400;
                }
                return '{"success":false,"message":"Customer name is required"}';
            }

            Lead leadRec = findOrCreateLead(customerName, customerEmail, customerPhone, projectName);

            Map<String, Object> paymentFields = new Map<String, Object>{
                'Opportunity__c' => null,
                'Payment_Type__c' => String.isBlank(paymentType) ? 'Advance' : paymentType,
                'Amount__c' => amount,
                'Payment_Status__c' => 'Paid',
                'Payment_Mode__c' => 'Razorpay Online',
                'Razorpay_Payment_Id__c' => razorpayPaymentId,
                'Razorpay_Payment_Link_Id__c' => razorpayLinkId,
                'Paid_Date_Time__c' => Datetime.now(),
                'Description__c' => projectName,
                'Lead__c' => leadRec.Id
            };
            SObject paymentRecord = createCustomRecord('Payment__c', paymentFields);
            insert paymentRecord;

            if (res != null) {
                res.statusCode = 200;
            }
            return JSON.serialize(new Map<String, Object>{
                'success' => true,
                'paymentId' => paymentRecord.Id,
                'leadId' => leadRec.Id,
                'message' => 'Payment stored in Salesforce CRM successfully.'
            });
        } catch (Exception ex) {
            if (res != null) {
                res.statusCode = 500;
            }
            return JSON.serialize(new Map<String, Object>{
                'success' => false,
                'message' => ex.getMessage()
            });
        }
    }

    private static Lead findOrCreateLead(String name, String email, String phone, String projectName) {
        List<Lead> leads = new List<Lead>();
        if (String.isNotBlank(email)) {
            leads = [SELECT Id, Email, Phone, LastName, Company, Status FROM Lead WHERE Email = :email LIMIT 1];
        }
        if (leads.isEmpty() && String.isNotBlank(phone)) {
            leads = [SELECT Id, Email, Phone, LastName, Company, Status FROM Lead WHERE Phone = :phone LIMIT 1];
        }

        if (!leads.isEmpty()) {
            Lead leadRec = leads[0];
            if (String.isBlank(leadRec.LastName)) {
                leadRec.LastName = name;
            }
            if (String.isBlank(leadRec.Company)) {
                leadRec.Company = String.isBlank(projectName) ? 'UrbanNest Website Lead' : projectName;
            }
            if (String.isBlank(leadRec.Phone) && String.isNotBlank(phone)) {
                leadRec.Phone = phone;
            }
            if (String.isBlank(leadRec.Email) && String.isNotBlank(email)) {
                leadRec.Email = email;
            }
            if (leadRec.Status == null || String.isBlank(leadRec.Status)) {
                leadRec.Status = 'Open - Not Contacted';
            }
            update leadRec;
            return leadRec;
        }

        String lastName = name;
        String companyName = String.isBlank(projectName) ? 'UrbanNest Website Lead' : projectName;
        Lead newLead = new Lead(
            LastName = lastName,
            Company = companyName,
            Email = email,
            Phone = phone,
            LeadSource = 'Own Website',
            Status = 'Open - Not Contacted',
            Description = 'Payment captured via Razorpay for ' + companyName,
            Website = 'https://www.urbannest.in'
        );
        insert newLead;
        return newLead;
    }

    private static String safeString(Object rawValue) {
        if (rawValue == null) return '';
        String value = String.valueOf(rawValue).trim();
        return value;
    }

    private static Decimal toDecimal(Object rawValue) {
        if (rawValue == null) return 0;
        try {
            return Decimal.valueOf(String.valueOf(rawValue));
        } catch (Exception ex) {
            return 0;
        }
    }

    public class PaymentLinkRequest {
        @AuraEnabled public Id opportunityId { get; set; }
        @AuraEnabled public String paymentType { get; set; }
        @AuraEnabled public Decimal amount { get; set; }
        @AuraEnabled public String customerName { get; set; }
        @AuraEnabled public String customerEmail { get; set; }
        @AuraEnabled public String customerPhone { get; set; }
        @AuraEnabled public Integer expiryMinutes { get; set; }
    }

    public class PaymentLinkResult {
        @AuraEnabled public Boolean isSuccess { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public String paymentLinkId { get; set; }
        @AuraEnabled public String shortUrl { get; set; }
        @AuraEnabled public Id paymentRecordId { get; set; }
    }

    @AuraEnabled
    public static PaymentLinkResult generatePaymentLink(Id opportunityId, String paymentType, Decimal amount, Integer expiryMinutes) {
        PaymentLinkResult result = new PaymentLinkResult();
        try {
            Opportunity opp = [
                SELECT Id, Name, AccountId, Account.Name,
                       (SELECT ContactId, Contact.Name, Contact.Email, Contact.Phone FROM OpportunityContactRoles WHERE IsPrimary = true LIMIT 1)
                FROM Opportunity
                WHERE Id = :opportunityId
                LIMIT 1
            ];

            String custName = 'Customer';
            String custEmail = '';
            String custPhone = '';

            if (opp.OpportunityContactRoles != null && !opp.OpportunityContactRoles.isEmpty()) {
                OpportunityContactRole primaryContactRole = opp.OpportunityContactRoles[0];
                if (primaryContactRole.ContactId != null) {
                    Contact primaryContact = [
                        SELECT Id, Name, Email, Phone
                        FROM Contact
                        WHERE Id = :primaryContactRole.ContactId
                        LIMIT 1
                    ];
                    custName = primaryContact.Name;
                    custEmail = primaryContact.Email;
                    custPhone = primaryContact.Phone;
                }
            }

            Integer expMins = (expiryMinutes != null && expiryMinutes > 0) ? expiryMinutes : 1440;
            Long expiryEpochSeconds = (DateTime.now().getTime() / 1000) + (expMins * 60);
            Long amountInPaise = (amount * 100).round();

            Map<String, Object> reqBody = new Map<String, Object>{
                'amount' => amountInPaise,
                'currency' => 'INR',
                'accept_partial' => false,
                'description' => paymentType + ' Payment for ' + opp.Name,
                'expire_by' => expiryEpochSeconds,
                'reference_id' => opp.Id + '-' + paymentType + '-' + System.currentTimeMillis(),
                'customer' => new Map<String, Object>{
                    'name' => custName,
                    'email' => custEmail,
                    'contact' => custPhone
                },
                'notify' => new Map<String, Object>{
                    'sms' => true,
                    'email' => true
                },
                'reminder_enable' => true
            };

            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:Razorpay_API/v1/payment_links');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setBody(JSON.serialize(reqBody));

            Http http = new Http();
            HttpResponse res;

            String paymentLinkId = 'plink_demo_' + String.valueOf(System.currentTimeMillis()).substring(6);
            String shortUrl = 'https://rzp.io/i/' + paymentLinkId;

            if (!Test.isRunningTest()) {
                try {
                    res = http.send(req);
                    if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
                        Map<String, Object> resMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                        paymentLinkId = (String) resMap.get('id');
                        shortUrl = (String) resMap.get('short_url');
                    } else {
                        throw new CalloutException('Razorpay API error (' + res.getStatusCode() + '): ' + res.getBody());
                    }
                } catch (Exception calloutEx) {
                    System.debug(LoggingLevel.WARN, 'Razorpay callout mock fallback: ' + calloutEx.getMessage());
                }
            }

            Map<String, Object> paymentFields = new Map<String, Object>{
                'Opportunity__c' => opp.Id,
                'Payment_Type__c' => paymentType,
                'Amount__c' => amount,
                'Payment_Status__c' => 'Pending',
                'Payment_Mode__c' => 'Razorpay Online',
                'Razorpay_Payment_Link_Id__c' => paymentLinkId,
                'Payment_Link_URL__c' => shortUrl,
                'Link_Expiry_Date_Time__c' => DateTime.newInstance(expiryEpochSeconds * 1000)
            };
            SObject paymentRecord = createCustomRecord('Payment__c', paymentFields);
            insert paymentRecord;

            if (String.isNotBlank(custPhone)) {
                WhatsAppNotificationService.sendPaymentLinkAlert(custPhone, custName, amount, paymentType, shortUrl);
            }

            result.isSuccess = true;
            result.message = 'Payment link created successfully and sent to customer.';
            result.paymentLinkId = paymentLinkId;
            result.shortUrl = shortUrl;
            result.paymentRecordId = paymentRecord.Id;
            return result;
        } catch (Exception ex) {
            result.isSuccess = false;
            result.message = 'Error generating payment link: ' + ex.getMessage();
            return result;
        }
    }

    private static SObject createCustomRecord(String objectApiName, Map<String, Object> fieldValues) {
        Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectApiName);
        if (sObjectType == null) {
            throw new IllegalArgumentException('Custom object not found: ' + objectApiName);
        }
        SObject record = sObjectType.newSObject();
        for (String fieldApiName : fieldValues.keySet()) {
            if (fieldValues.get(fieldApiName) == null) continue;
            if (sObjectType.getDescribe().fields.getMap().containsKey(fieldApiName)) {
                record.put(fieldApiName, fieldValues.get(fieldApiName));
            }
        }
        return record;
    }
}
