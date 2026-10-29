# Map definitions: playable regions (display name -> lon/lat geometry), play bbox, hilly regions.
from geo import *
def A1(admin, field, vals):
    vals = set([vals] if isinstance(vals, str) else vals)
    return unary_union([g for d, g in adm1(admin, lambda d: d[field] in vals)])
def SPLIT(admin, k, names, clip=None, pred=None):
    it = adm1(admin, pred)
    if clip is not None: it = [(d, g.intersection(clip)) for d, g in it]; it = [(d, g) for d, g in it if not g.is_empty and g.area > 1e-4]
    parts = kmeans_split(it, k); whole = unary_union(parts)
    out = []
    for p in parts:
        cp = compass(p, whole); out.append((names.get(cp, cp + ' ' + admin), p))
    return out

def greece():
    G = lambda *n: A1('Greece', 'name_en', n)
    R = [('Macedonia', G('Centre Macedonia', 'Mount Athos')), ('W. Macedonia', G('West Macedonia')), ('Epirus', G('Epirus')),
         ('Thrace', G('East Macedonia and Thrace')), ('Thessaly', G('Thessalia')), ('Sterea', G('Central Greece')),
         ('Attica', G('Attica')), ('Peloponnese', G('Peloponnese')), ('W. Greece', G('West Greece')), ('Crete', G('Crete')),
         ('Cyclades', G('South Aegean')), ('N. Aegean', G('North Aegean')), ('Ionian Isles', G('Ionian Islands'))]
    return dict(bbox=(19.2, 34.6, 29.0, 41.9), regions=R, hills={'W. Macedonia', 'Epirus'})

def balkans():
    clip = box(13.3, 39.4, 30.2, 48.4)
    R = [(n, country(n)) for n in ('Slovenia', 'Croatia', 'Montenegro', 'Kosovo', 'Albania', 'North Macedonia', 'Moldova', 'Hungary')]
    R += [('Bosnia', country('Bosnia and Herzegovina')), ('Serbia', country('Republic of Serbia'))]
    R += SPLIT('Romania', 3, {'NW': 'Transylvania', 'West': 'Transylvania', 'North': 'Moldavia', 'NE': 'Moldavia', 'East': 'Dobruja',
                              'SE': 'Wallachia', 'South': 'Wallachia', 'SW': 'Banat'})
    R += SPLIT('Bulgaria', 2, {'West': 'Sofia', 'SW': 'Sofia', 'NW': 'Sofia', 'East': 'Varna', 'NE': 'Varna', 'SE': 'Varna'})
    gr = lambda *n: A1('Greece', 'name_en', n)
    R += [('Macedonia', gr('Centre Macedonia', 'West Macedonia', 'Mount Athos')), ('Thrace', gr('East Macedonia and Thrace')),
          ('Epirus', gr('Epirus', 'Thessalia').intersection(clip)), ('E. Thrace', country('Turkey').intersection(box(25, 40.3, 29.2, 42.2)))]
    R = [(n, g.intersection(clip)) for n, g in R]
    return dict(bbox=(13.3, 39.4, 30.2, 48.4), regions=R, hills={'Montenegro', 'Kosovo', 'Bosnia', 'Transylvania', 'Sofia'})

def italy():
    I = lambda *n: A1('Italy', 'region', n)
    R = [('Piedmont', I('Piemonte', "Valle d'Aosta")), ('Lombardy', I('Lombardia')), ('Trentino', I('Trentino-Alto Adige')),
         ('Veneto', I('Veneto')), ('Friuli', I('Friuli-Venezia Giulia')), ('Liguria', I('Liguria')), ('Emilia', I('Emilia-Romagna')),
         ('Tuscany', I('Toscana')), ('Umbria', I('Umbria')), ('Marche', I('Marche')), ('Lazio', I('Lazio')),
         ('Abruzzo', I('Abruzzo', 'Molise')), ('Campania', I('Campania')), ('Apulia', I('Apulia')), ('Basilicata', I('Basilicata')),
         ('Calabria', I('Calabria')), ('Sicily', I('Sicily')), ('Sardinia', I('Sardegna'))]
    return dict(bbox=(6.5, 36.5, 18.6, 47.1), regions=R, hills={'Trentino', 'Abruzzo', 'Basilicata', 'Piedmont'})

def iberia():
    S = lambda *n: A1('Spain', 'region', n)
    R = [('Galicia', S('Galicia')), ('Asturias', S('Asturias', 'Cantabria')), ('Basque', S('País Vasco', 'Foral de Navarra', 'La Rioja')),
         ('Aragon', S('Aragón')), ('Catalonia', S('Cataluña')), ('León', S('Castilla y León')), ('Madrid', S('Madrid')),
         ('La Mancha', S('Castilla-La Mancha')), ('Valencia', S('Valenciana')), ('Murcia', S('Murcia')), ('Extremadura', S('Extremadura')),
         ('Andalusia', S('Andalucía')), ('Baleares', S('Islas Baleares'))]
    R += SPLIT('Portugal', 3, {'North': 'Porto', 'NE': 'Porto', 'NW': 'Porto', 'West': 'Lisbon', 'East': 'Lisbon', 'SW': 'Lisbon', 'South': 'Algarve', 'SE': 'Algarve'},
               clip=box(-10, 36.8, -6, 42.2))
    return dict(bbox=(-9.8, 35.9, 4.5, 43.9), regions=R, hills={'Asturias', 'Aragon', 'Basque'})

def europe():
    clip = box(-11, 35.5, 32.5, 61.0)
    one = ['Portugal', 'Ireland', 'Netherlands', 'Denmark', 'Norway', 'Finland', 'Estonia', 'Latvia', 'Lithuania', 'Czechia', 'Slovakia',
           'Austria', 'Switzerland', 'Slovenia', 'Croatia', 'Montenegro', 'Kosovo', 'Albania', 'North Macedonia', 'Bulgaria', 'Moldova',
           'Hungary', 'Belarus']
    R = [(n, country(n)) for n in one]
    R += [('Belgium', unary_union([country('Belgium'), country('Luxembourg')])), ('Bosnia', country('Bosnia and Herzegovina')),
          ('Serbia', country('Republic of Serbia'))]
    cmp = {'North': 'N.', 'South': 'S.', 'East': 'E.', 'West': 'W.', 'NE': 'N.', 'NW': 'N.', 'SE': 'S.', 'SW': 'S.'}
    def sp(admin, k, short, pred=None, clipg=None):
        out = []
        for n, g in SPLIT(admin, k, {}, clip=clipg, pred=pred): out.append((cmp.get(n.split(' ')[0], '') + ' ' + short, g))
        return out
    metro = box(-6, 41, 10, 51.5)
    R += sp('France', 3, 'France', clipg=metro) + sp('Spain', 2, 'Spain', clipg=box(-10, 35.9, 4, 44)) + sp('Germany', 2, 'Germany')
    R += sp('Poland', 2, 'Poland') + sp('Italy', 2, 'Italy') + sp('United Kingdom', 2, 'Britain') + sp('Sweden', 2, 'Sweden', clipg=clip)
    R += sp('Romania', 2, 'Romania') + sp('Ukraine', 2, 'Ukraine', clipg=box(22, 44, 32.5, 53)) + sp('Greece', 2, 'Greece')
    R = [(n, g.intersection(clip)) for n, g in R]
    return dict(bbox=(-10.5, 35.6, 32.0, 61.0), regions=R, hills={'Switzerland', 'Austria', 'Norway', 'Slovakia', 'Montenegro', 'Kosovo', 'Bosnia'})

def usa():
    st = lambda *n: A1('United States of America', 'name', n)
    names = ['Washington', 'Oregon', 'California', 'Nevada', 'Idaho', 'Montana', 'Wyoming', 'Utah', 'Arizona', 'Colorado', 'New Mexico',
             'North Dakota', 'South Dakota', 'Nebraska', 'Kansas', 'Oklahoma', 'Texas', 'Minnesota', 'Iowa', 'Missouri', 'Arkansas',
             'Louisiana', 'Wisconsin', 'Illinois', 'Michigan', 'Indiana', 'Ohio', 'Kentucky', 'Tennessee', 'Mississippi', 'Alabama',
             'Georgia', 'Florida', 'South Carolina', 'North Carolina', 'Virginia', 'West Virginia', 'Pennsylvania', 'New York']
    R = [(n, st(n)) for n in names]
    R += [('New England', st('Maine', 'New Hampshire', 'Vermont', 'Massachusetts', 'Rhode Island', 'Connecticut')),
          ('Mid-Atlantic', st('New Jersey', 'Delaware', 'Maryland', 'District of Columbia'))]
    return dict(bbox=(-124.8, 24.4, -66.8, 49.4), regions=R, proj=(-96, 37.5, 29.5, 45.5),
                hills={'Colorado', 'Utah', 'Wyoming', 'Idaho', 'Montana', 'Nevada', 'West Virginia'})

# ------------------------------------------------------------------ global maps: accurate outline + gameplay partition (config only)
def OUT(title, bbox, k, names=None, continent=None, clip=None, lab=1, extra=(), **kw):
    """title, play bbox (lon0, lat0, lon1, lat1), region count k, outline = NE admin-0 countries by name or continent."""
    clip = clip or bbox
    o = outline(names=names, continent=continent, clip=clip, exclude=kw.pop('exclude', ()))
    L = label_points(lab, admins=names if lab == 1 else (names if names and not continent else None), continent=continent, clip=clip)
    L += [(n, lo, la, 0.5) for n, lo, la in extra]
    return dict(title=title, bbox=bbox, outline=o, k=k, labels=L, **kw)

def india(): return OUT('India', (67.5, 5.8, 97.5, 35.6), 16, names=['India', 'Sri Lanka'], islands=0.25, hills_ll=[(77, 34), (79, 30.5), (93, 26.5), (76.5, 11.5)])
def china(): return OUT('China', (73, 18, 135, 53.6), 20, names=['China'], hills_ll=[(88, 32), (99, 30), (82, 43), (103, 25.5)])
def japan(): return OUT('Japan', (129, 30.8, 146, 45.6), 10, names=['Japan'], clip=(128.5, 30.8, 146, 45.7), hills_ll=[(138, 36.2), (140.5, 39.5)])
def asia(): return OUT('Asia', (26, -10.5, 146, 55), 30, continent='Asia', lab=0, hills_ll=[(85, 30), (72, 38), (46, 38), (100, 33)],
                       extra=[('Siberia', 105, 52), ('Borneo', 114, 1), ('Sumatra', 101, 0), ('Arabia', 46, 23), ('Tibet', 88, 32)])
def africa(): return OUT('Africa', (-18, -35, 52, 37.6), 28, continent='Africa', lab=0, hills_ll=[(38, 8), (30, -2), (-5, 31.5), (37, -3)],
                         extra=[('Sahara', 10, 24), ('Sahel', 5, 15), ('Kalahari', 22, -23), ('Congo Basin', 21, 0), ('Horn', 46, 8)])
def westafrica(): return OUT('West Africa', (-17.8, 4, 15.5, 15.6), 16, clip=(-18, 4, 16, 15.6), lab=1,
    names=['Senegal', 'Gambia', 'Guinea-Bissau', 'Guinea', 'Sierra Leone', 'Liberia', 'Ivory Coast', "Côte d'Ivoire", 'Ghana', 'Togo', 'Benin',
           'Nigeria', 'Burkina Faso', 'Mali', 'Niger'], hills_ll=[(-10.5, 10.5), (9, 10)])
def southafrica(): return OUT('Southern Africa', (11.5, -35, 41, -15.5), 16, clip=(11, -35, 41.5, -15.5), lab=0,
    names=['South Africa', 'Lesotho', 'eSwatini', 'Namibia', 'Botswana', 'Zimbabwe', 'Mozambique'], hills_ll=[(28.3, -29.5), (30, -24)],
    extra=[('Cape', 19.5, -33.5), ('Karoo', 22, -32), ('Kalahari', 22, -23), ('Natal', 30.5, -29), ('Highveld', 28, -26), ('Skeleton Coast', 13.5, -20),
           ('Okavango', 22.5, -19.5), ('Limpopo', 32, -23), ('Zambezi', 34, -17), ('Namib', 15.5, -25), ('Transkei', 28.5, -31.7), ('Bushveld', 26, -24.5)])
def australia(): return OUT('Australia', (112.5, -44, 154, -10.5), 14, names=['Australia'], clip=(112, -44, 154, -10), lab=1, islands=0.3, hills_ll=[(146.5, -37), (149, -33)],
    extra=[('Kimberley', 126, -17), ('Pilbara', 119, -22), ('Nullarbor', 129, -30.5), ('Red Centre', 133.5, -24), ('Top End', 132.5, -13.5), ('Cape York', 143, -14),
           ('Gulf Country', 139, -18), ('Riverina', 146, -35), ('Goldfields', 121.5, -30.5), ('Outback', 140, -27), ('Gippsland', 147.5, -37.8)])
def nz(): return OUT('New Zealand', (166, -47.5, 178.8, -34.3), 8, names=['New Zealand'], clip=(165.5, -47.6, 179, -34), hills_ll=[(170.5, -43.5), (175.6, -39.2)],
                 sea_labels=[('Tasman Sea', 168.2, -38.3, 1.0), ('<  Australia  ·  2,000 km', 165.6, -42.6, 0.8), ('South Pacific Ocean', 178.6, -44.3, 1.0)])
def brazil(): return OUT('Brazil', (-74, -33.8, -34.5, 5.4), 16, names=['Brazil'], hills_ll=[(-43.5, -19.5), (-48, -16)],
    extra=[('Amazonia', -63, -4), ('Pantanal', -57, -18), ('Sertao', -40, -9), ('Cerrado', -47, -12)])
def southamerica(): return OUT('South America', (-82, -55.9, -34.5, 12.6), 22, continent='South America', lab=0, clip=(-82, -56, -34, 13),
    hills_ll=[(-70, -18), (-75, -10), (-69, -33), (-73.5, 4)],
    extra=[('Patagonia', -69, -46), ('Amazonia', -63, -4), ('Pampas', -62, -36), ('Atacama', -69.5, -24), ('Gran Chaco', -61, -23), ('Mato Grosso', -55, -13),
           ('Llanos', -69, 6.5), ('Altiplano', -67.5, -18.5), ('Cerrado', -47, -12), ('Tierra del Fuego', -68, -54), ('Sertao', -40, -9), ('Guiana', -57, 4.5)])
def mexico(): return OUT('Mexico', (-117.5, 14.4, -86.6, 32.8), 12, names=['Mexico'], hills_ll=[(-104.5, 25), (-99, 19), (-96.5, 17)])
def world(): return OUT('The World', (-180, -56, 180, 83.7), 40, continent=['Europe', 'Asia', 'Africa', 'North America', 'South America', 'Oceania'],
    pad=.12, lab=0, clip=(-180, -56, 180, 84), proj='ee', lon0=10.0, minlat=-60, tol=0.12, exclude=('Greenland',) if False else (),
    hills_ll=[(85, 30), (-70, -18), (-110, 42), (38, 8), (10, 46)],
    extra=[('Siberia', 105, 60), ('Sahara', 10, 24), ('Amazonia', -63, -4), ('Patagonia', -69, -46), ('Outback', 134, -25), ('Arctic', -100, 68),
           ('Yukon', -135, 63), ('Kamchatka', 160, 58), ('Ural', 60, 58), ('Greenland', -42, 72)])

for _k, _t in dict(greece='Greece', balkans='The Balkans', italy='Italy', iberia='Iberia', europe='Europe', usa='United States').items():
    _f = globals()[_k]; globals()[_k] = (lambda f, t: (lambda: dict(f(), title=t)))(_f, _t)
MAPS = dict(greece=greece, balkans=balkans, italy=italy, iberia=iberia, europe=europe, usa=usa,
            india=india, china=china, japan=japan, asia=asia, africa=africa, westafrica=westafrica, southafrica=southafrica,
            australia=australia, nz=nz, brazil=brazil, southamerica=southamerica, mexico=mexico, world=world)
