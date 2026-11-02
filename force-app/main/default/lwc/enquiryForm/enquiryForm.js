import { LightningElement, api, track, wire } from 'lwc';
import submitEnquiry from '@salesforce/apex/EnquiryController.submitEnquiry';
import getActiveProjects from '@salesforce/apex/EnquiryController.getActiveProjects';

export default class EnquiryForm extends LightningElement {
    @api defaultProjectId;

    @track formData = {
        firstName: '',
        lastName: '',
        email: '',
        phone: '',
        budget: null,
        bhkPreference: '2 BHK',
        projectId: '',
        remarks: ''
    };

    @track projectOptions = [];
    @track isLoading = false;
    @track notificationMessage = '';
    @track notificationClass = '';

    bhkOptions = [
        { label: '1 BHK', value: '1 BHK' },
        { label: '2 BHK', value: '2 BHK' },
        { label: '3 BHK', value: '3 BHK' }
    ];

    connectedCallback() {
        if (this.defaultProjectId) {
            this.formData.projectId = this.defaultProjectId;
        }
    }

    @wire(getActiveProjects)
    wiredProjects({ error, data }) {
        if (data) {
            this.projectOptions = data.map(item => ({
                label: item.name + (item.state ? ' (' + item.state + ')' : ''),
                value: item.id
            }));
            if (!this.formData.projectId && this.projectOptions.length > 0) {
                this.formData.projectId = this.projectOptions[0].value;
            }
        } else if (error) {
            console.error('Error loading projects for enquiry form', error);
        }
    }

    handleInputChange(event) {
        const field = event.target.dataset.field;
        this.formData[field] = event.target.value;
    }

    handleSubmit() {
        // Simple form validation
        if (!this.formData.lastName || (!this.formData.phone && !this.formData.email)) {
            this.showBanner('Please fill in required fields: Last Name and either Phone or Email.', false);
            return;
        }

        this.isLoading = true;
        this.notificationMessage = '';

        submitEnquiry({ request: this.formData })
            .then(result => {
                this.isLoading = false;
                if (result.isSuccess) {
                    this.showBanner(result.message, true);
                    this.resetForm();
                } else {
                    this.showBanner(result.message, false);
                }
            })
            .catch(error => {
                this.isLoading = false;
                const err = error.body ? error.body.message : error.message;
                this.showBanner('Submission error: ' + err, false);
            });
    }

    showBanner(message, isSuccess) {
        this.notificationMessage = message;
        this.notificationClass = isSuccess 
            ? 'slds-notify slds-notify_alert slds-alert_success slds-m-bottom_medium'
            : 'slds-notify slds-notify_alert slds-alert_error slds-m-bottom_medium';
    }

    resetForm() {
        this.formData = {
            firstName: '',
            lastName: '',
            email: '',
            phone: '',
            budget: null,
            bhkPreference: '2 BHK',
            projectId: this.defaultProjectId || (this.projectOptions[0] ? this.projectOptions[0].value : ''),
            remarks: ''
        };
    }
}
