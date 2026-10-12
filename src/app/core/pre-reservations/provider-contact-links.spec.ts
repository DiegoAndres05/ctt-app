import { providerContactLinks } from './provider-contact-links';

describe('providerContactLinks', () => {
  it('builds tel, wa.me and mailto links from a full snapshot', () => {
    expect(
      providerContactLinks({
        provider_phone: '+57 300 111 2233',
        provider_email: 'ventas@lanchasbaru.co',
      }),
    ).toEqual({
      tel: 'tel:+573001112233',
      whatsapp: 'https://wa.me/573001112233',
      mailto: 'mailto:ventas@lanchasbaru.co',
    });
  });

  it('omits both phone links when there is no phone', () => {
    expect(providerContactLinks({ provider_phone: null, provider_email: null })).toEqual({});
    expect(providerContactLinks({})).toEqual({});
  });

  it('omits mailto when there is no email', () => {
    expect(providerContactLinks({ provider_phone: '300 111 2233' })).toEqual({
      tel: 'tel:3001112233',
      whatsapp: 'https://wa.me/3001112233',
    });
  });

  it('skips wa.me when the phone has no digits', () => {
    expect(providerContactLinks({ provider_phone: 's/n', provider_email: '  ' })).toEqual({
      tel: 'tel:s/n',
    });
  });
});
