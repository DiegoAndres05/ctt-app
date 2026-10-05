import {
  REQUEST_CHANNEL_LABELS,
  REQUEST_STATUS_LABELS,
  availableStatusActions,
  isRequestClosed,
  type RequestChannel,
  type RequestStatus,
} from './request.model';

const STATUSES: RequestStatus[] = ['received', 'in_review', 'discarded', 'pre_reservation'];
const CHANNELS: RequestChannel[] = ['web', 'whatsapp', 'phone', 'in_person'];

describe('availableStatusActions', () => {
  it('offers review and discard from received, and never pre_reservation', () => {
    expect(availableStatusActions('received')).toEqual(['in_review', 'discarded']);
    expect(availableStatusActions('received')).not.toContain('pre_reservation');
  });

  it('offers only discard from in_review', () => {
    expect(availableStatusActions('in_review')).toEqual(['discarded']);
  });

  it('offers nothing once the request is closed', () => {
    expect(availableStatusActions('discarded')).toEqual([]);
    expect(availableStatusActions('pre_reservation')).toEqual([]);
  });
});

describe('isRequestClosed', () => {
  it('is true only for discarded and pre_reservation', () => {
    expect(isRequestClosed('discarded')).toBe(true);
    expect(isRequestClosed('pre_reservation')).toBe(true);
    expect(isRequestClosed('received')).toBe(false);
    expect(isRequestClosed('in_review')).toBe(false);
  });
});

describe('labels', () => {
  it('has a Spanish label for every status and channel', () => {
    for (const status of STATUSES) {
      expect(REQUEST_STATUS_LABELS[status].length).toBeGreaterThan(0);
    }
    for (const channel of CHANNELS) {
      expect(REQUEST_CHANNEL_LABELS[channel].length).toBeGreaterThan(0);
    }
  });
});
