import { LightningElement, track, wire } from 'lwc';
import getActiveProjects from '@salesforce/apex/EnquiryController.getActiveProjects';

export default class SiteVisitScheduler extends LightningElement {
    @track formData = {
        name: '',
        phone: '',
        projectId: '',
        visitDate: '',
        needCab: true,
        pickupAddress: '',
        passengers: '2',
        vehicleType: 'Sedan'
    };

    @track projectOptions = [];
    @track isSuccess = false;

    passengerOptions = [
        { label: '1 Passenger', value: '1' },
        { label: '2 Passengers', value: '2' },
        { label: '3 Passengers', value: '3' },
        { label: '4 Passengers', value: '4' }
    ];

    vehicleOptions = [
        { label: 'Executive Sedan (Dzire / Etios)', value: 'Sedan' },
        { label: 'Luxury SUV (Innova Crysta)', value: 'SUV' },
        { label: 'Electric Vehicle (Nexon EV)', value: 'EV' }
    ];

    @wire(getActiveProjects)
    wiredProjects({ error, data }) {
        if (data) {
            this.projectOptions = data.map(p => ({
                label: p.name + (p.state ? ' (' + p.state + ')' : ''),
                value: p.id
            }));
            if (this.projectOptions.length > 0) {
                this.formData.projectId = this.projectOptions[0].value;
            }
        }
    }

    handleFieldChange(event) {
        const field = event.target.dataset.field;
        this.formData[field] = event.target.value;
    }

    handleCabToggle(event) {
        this.formData.needCab = event.target.checked;
    }

    handleSubmit() {
        if (!this.formData.name || !this.formData.phone || !this.formData.visitDate) {
            alert('Please fill in required fields: Name, Phone, and Visit Date.');
            return;
        }
        this.isSuccess = true;
    }
}
