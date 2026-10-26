import { FUNNEL_STAGE_LABELS, canClientComputeMetrics, formatRate } from './analytics.model';

describe('analytics.model', () => {
  it('labels every funnel stage in Spanish', () => {
    expect(FUNNEL_STAGE_LABELS.requests).toBe('Solicitudes');
    expect(FUNNEL_STAGE_LABELS.reservations_confirmed).toBe('Reservas confirmadas');
  });

  it('forbids client-side metric math', () => {
    expect(canClientComputeMetrics).toBe(false);
  });

  it('renders null rates as an em dash', () => {
    expect(formatRate(null)).toBe('—');
    expect(formatRate(0.5)).toBe('50.0 %');
  });
});
