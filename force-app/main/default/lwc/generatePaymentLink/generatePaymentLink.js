import { LightningElement, api, track } from 'lwc';
import generatePaymentLink from '@salesforce/apex/RazorpayPaymentService.generatePaymentLink';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class GeneratePaymentLink extends LightningElement {
    @api recordId; // Opportunity ID

    @track paymentType = 'Advance';
    @track amount = 100000;
    @track expiryHours = '24';
    @track isLoading = false;
    @track linkGenerated = false;
    @track shortUrl = '';

    paymentTypeOptions = [
        { label: 'Advance Payment', value: 'Advance' },
        { label: 'Settlement Payment', value: 'Settlement' }
    ];

    expiryOptions = [
        { label: '12 Hours', value: '12' },
        { label: '24 Hours (1 Day)', value: '24' },
        { label: '48 Hours (2 Days)', value: '48' },
        { label: '72 Hours (3 Days)', value: '72' }
    ];

    handleTypeChange(event) {
        this.paymentType = event.target.value;
    }

    handleAmountChange(event) {
        this.amount = parseFloat(event.target.value);
    }

    handleExpiryChange(event) {
        this.expiryHours = event.target.value;
    }

    handleGenerate() {
        if (!this.amount || this.amount <= 0) {
            this.showToast('Error', 'Please enter a valid payment amount.', 'error');
            return;
        }

        this.isLoading = true;
        const expiryMinutes = parseInt(this.expiryHours, 10) * 60;

        generatePaymentLink({
            opportunityId: this.recordId,
            paymentType: this.paymentType,
            amount: this.amount,
            expiryMinutes: expiryMinutes
        })
        .then(result => {
            this.isLoading = false;
            if (result.isSuccess) {
                this.linkGenerated = true;
                this.shortUrl = result.shortUrl;
                this.showToast('Success', result.message, 'success');
            } else {
                this.showToast('Error', result.message, 'error');
            }
        })
        .catch(error => {
            this.isLoading = false;
            const msg = error.body ? error.body.message : error.message;
            this.showToast('Error', msg, 'error');
        });
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
