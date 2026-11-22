# v1 model on dummy user inputs

Made-up test profiles, not real users. Every card is checked against the hard filters.

## Dinner in Brooklyn, mid-range

Input: borough=Brooklyn, max_price=2, categories=['Restaurants'], toggles=[]  
Nearest cluster: **16 · Mid-range restaurants · outdoor, drinks**  
Clusters used: 4 · matching places in catalog: 4,951 · deck size: 10 · all cards pass filters: yes

| # | place | type | price | rating | neighborhood | cluster |
|---|---|---|---|---|---|---|
| 1 | Glin Thai Bistro | Thai Restaurant | $$ | 4.9 (5,781) | Fort Greene, Brooklyn | 23 |
| 2 | Khaosan | Thai Restaurant | $$ | 4.9 (4,269) | Brooklyn Heights, Brooklyn | 16 |
| 3 | Ler Lers | Thai Restaurant | $$ | 4.9 (3,612) | Bedford-Stuyvesant (West), Brooklyn | 16 |
| 4 | Isla & Co - Williamsburg | Restaurant | $$ | 4.9 (2,481) | Williamsburg, Brooklyn | 6 |
| 5 | Laghman Express | Halal Restaurant | $$ | 4.9 (1,614) | Sheepshead Bay-Manhattan Beach-Gerritsen Beach, Brooklyn | 6 |
| 6 | Maison Provence Restaurant | French Restaurant | $$ | 4.9 (999) | Williamsburg, Brooklyn | 16 |
| 7 | Macoletta | Pizza Restaurant | $$ | 4.9 (945) | Williamsburg, Brooklyn | 23 |
| 8 | 18th Ave Cafe G | Eastern European Restaurant | $$ | 4.9 (842) | Bensonhurst, Brooklyn | 16 |
| 9 | Knori Hand Roll Bar | Japanese Restaurant | $$ | 4.9 (568) | Greenpoint, Brooklyn | 23 |
| 10 | Mumbai Place | Indian Restaurant | $$ | 4.9 (430) | Williamsburg, Brooklyn | 6 |

## Free culture in Manhattan

Input: borough=Manhattan, max_price=0, categories=['Museums & Galleries'], toggles=[]  
Nearest cluster: **9 · Budget museums & galleries**  
Clusters used: 1 · matching places in catalog: 903 · deck size: 10 · all cards pass filters: yes

| # | place | type | price | rating | neighborhood | cluster |
|---|---|---|---|---|---|---|
| 1 | G-Gallery | Art Gallery | Free | 5.0 (238) | Tribeca-Civic Center, Manhattan | 9 |
| 2 | Galleria On Third | Store | Free | 4.9 (320) | East Midtown-Turtle Bay, Manhattan | 9 |
| 3 | Kate Oh Gallery, LLC | Art Gallery | Free | 5.0 (126) | Upper East Side-Carnegie Hill, Manhattan | 9 |
| 4 | Salmagundi Club | Art Gallery | Free | 4.8 (273) | Greenwich Village, Manhattan | 9 |
| 5 | Decor Art Gallery | Store | Free | 5.0 (57) | Murray Hill-Kips Bay, Manhattan | 9 |
| 6 | Philip Williams Posters | Store | Free | 4.7 (347) | Tribeca-Civic Center, Manhattan | 9 |
| 7 | Japan Society | Cultural Center | Free | 4.6 (759) | East Midtown-Turtle Bay, Manhattan | 9 |
| 8 | Artists Space | Association / Organization | Free | 4.7 (77) | Tribeca-Civic Center, Manhattan | 9 |
| 9 | Piragua Art Space | Cultural Center | Free | 5.0 (22) | East Village, Manhattan | 9 |
| 10 | Bhakti Marga NYC | Cultural Center | Free | 5.0 (20) | Midtown South-Flatiron-Union Square, Manhattan | 9 |

## Cheap park day with kids, Queens

Input: borough=Queens, max_price=1, categories=['Parks & Outdoors'], toggles=['kids']  
Nearest cluster: **0 · Free parks & outdoors · outdoor, family-friendly**  
Clusters used: 1 · matching places in catalog: 781 · deck size: 10 · all cards pass filters: yes

| # | place | type | price | rating | neighborhood | cluster |
|---|---|---|---|---|---|---|
| 1 | Gantry Plaza State Park | State Park | Free | 4.8 (10,319) | Long Island City-Hunters Point, Queens | 0 |
| 2 | Hunter's Point South Park | Park | Free | 4.8 (5,616) | Long Island City-Hunters Point, Queens | 0 |
| 3 | Astoria Park | Park | Free | 4.7 (13,137) | Astoria Park, Queens | 0 |
| 4 | Juniper Valley Park | Park | Free | 4.7 (4,589) | Middle Village, Queens | 0 |
| 5 | Alley Pond Environmental Center | Nature Preserve | Free | 4.7 (531) | Alley Pond Park, Queens | 0 |
| 6 | Juniper South Playground | Playground | Free | 4.7 (283) | Middle Village, Queens | 0 |
| 7 | Kissena Park Playground | Playground | Free | 4.7 (259) | Kissena Park, Queens | 0 |
| 8 | Forest Park Hiking Trails | Hiking Area | Free | 4.8 (83) | Forest Park, Queens | 0 |
| 9 | Hunter's Point South Park Playground | Playground | Free | 4.9 (52) | Long Island City-Hunters Point, Queens | 0 |
| 10 | All Dogs In The City | Pet Care | Free | 4.7 (84) | Astoria (North)-Ditmars-Steinway, Queens | 0 |

## Night out anywhere, upscale

Input: borough=any, max_price=3, categories=['Bars & Nightlife'], toggles=['nightlife']  
Nearest cluster: **4 · Mid-range bars · late-night, drinks**  
Clusters used: 1 · matching places in catalog: 2,700 · deck size: 10 · all cards pass filters: yes

| # | place | type | price | rating | neighborhood | cluster |
|---|---|---|---|---|---|---|
| 1 | Sorso' | Wine Bar | $$$ | 4.9 (832) | Greenwich Village, Manhattan | 4 |
| 2 | Le Vin Coeur | Bar | $$$ | 5.0 (176) | Upper West Side (Central), Manhattan | 4 |
| 3 | Ms. Alice | Cocktail Bar | $$$ | 4.9 (566) | Lower East Side, Manhattan | 4 |
| 4 | Flairmaison Bar and Lounge | Cocktail Bar | $$$ | 5.0 (155) | Chelsea-Hudson Yards, Manhattan | 4 |
| 5 | Barlume Downstairs | Cocktail Bar | $$$ | 4.9 (347) | Midtown South-Flatiron-Union Square, Manhattan | 4 |
| 6 | Live Axe | Bar | $$$ | 4.8 (3,566) | Tribeca-Civic Center, Manhattan | 4 |
| 7 | The Last Stop | Bar | $$$ | 4.8 (1,261) | Kingsbridge-Marble Hill, Bronx | 4 |
| 8 | Rosa – Agave & Wine Lounge | Wine Bar | $$$ | 4.9 (175) | Tribeca-Civic Center, Manhattan | 4 |
| 9 | NOFLEX® NYC | Lounge bar | $$$ | 4.7 (1,146) | Midtown South-Flatiron-Union Square, Manhattan | 4 |
| 10 | Ruffian | Wine Bar | $$$ | 4.7 (446) | East Village, Manhattan | 4 |

## Luxury spa, Staten Island (edge case)

Input: borough=Staten Island, max_price=4, categories=['Spas & Wellness'], toggles=[]  
Nearest cluster: **2 · Upscale spas & wellness**  
Clusters used: 1 · matching places in catalog: 130 · deck size: 10 · all cards pass filters: yes

| # | place | type | price | rating | neighborhood | cluster |
|---|---|---|---|---|---|---|
| 1 | Luna Hair Salon | Hair Salon | $$$$ | 5.0 (84) | Grasmere-Arrochar-South Beach-Dongan Hills, Staten Island | 2 |
| 2 | GoldenGlow | Beauty Salon | $$$$ | 4.9 (81) | Todt Hill-Emerson Hill-Lighthouse Hill-Manor Heights, Staten Island | 2 |
| 3 | Ted & Company Salon | Beauty Salon | $$$$ | 4.6 (185) | Grasmere-Arrochar-South Beach-Dongan Hills, Staten Island | 2 |
| 4 | The Formula by Nicole Frontera | Spa | $$$ | 5.0 (237) | Great Kills-Eltingville, Staten Island | 2 |
| 5 | Rivieree Scalp Treatment and Spa | Spa | $$$ | 4.9 (358) | Tottenville-Charleston, Staten Island | 2 |
| 6 | Facial Spa La Jolie | Beauty Salon | $$$ | 5.0 (128) | Todt Hill-Emerson Hill-Lighthouse Hill-Manor Heights, Staten Island | 2 |
| 7 | Muyan Spa Beauty & Scalp Treatment | Spa | $$$ | 4.9 (258) | New Dorp-Midland Beach, Staten Island | 2 |
| 8 | Aruna SPA Microblading Staten Island | Body art service | $$$ | 4.9 (135) | Westerleigh-Castleton Corners, Staten Island | 2 |
| 9 | Skin Solutions Spa & Centre | Medical Clinic | $$$ | 4.8 (251) | Freshkills Park (South), Staten Island | 2 |
| 10 | 2 Relaxing Spa Inc. | Massage spa | $$$ | 4.7 (144) | Westerleigh-Castleton Corners, Staten Island | 2 |

## Coffee + books, Manhattan

Input: borough=Manhattan, max_price=1, categories=['Cafes & Desserts', 'Libraries & Bookstores'], toggles=[]  
Nearest cluster: **17 · Budget cafes & desserts · late-night**  
Clusters used: 3 · matching places in catalog: 1,754 · deck size: 10 · all cards pass filters: yes

| # | place | type | price | rating | neighborhood | cluster |
|---|---|---|---|---|---|---|
| 1 | Rito Gelato | Ice Cream Shop | $ | 5.0 (640) | Upper West Side (Central), Manhattan | 17 |
| 2 | Soho News International | Book Store | $ | 4.9 (1,345) | SoHo-Little Italy-Hudson Square, Manhattan | 12 |
| 3 | Spoonable Spirits | Dessert Shop | $ | 5.0 (422) | Upper East Side-Yorkville, Manhattan | 3 |
| 4 | Midtown Comics Downtown | Book Store | $ | 4.7 (1,452) | Financial District-Battery Park City, Manhattan | 12 |
| 5 | 787 Coffee | Coffee Shop | $ | 4.9 (4,970) | West Village, Manhattan | 3 |
| 6 | Midtown Comics Times Square | Book Store | $ | 4.6 (9,793) | Midtown-Times Square, Manhattan | 12 |
| 7 | Figo il Gelato Italiano | Ice Cream Shop | $ | 4.9 (2,680) | Greenwich Village, Manhattan | 17 |
| 8 | Iconic Magazines - Lafayette | Convenience Store | $ | 4.3 (8) | SoHo-Little Italy-Hudson Square, Manhattan | 12 |
| 9 | Gold coffee | Coffee Shop | $ | 4.9 (1,970) | Murray Hill-Kips Bay, Manhattan | 3 |
| 10 | Lady Konfidential | Store | Free | 5.0 (106) | Midtown-Times Square, Manhattan | 12 |

## Live show, Manhattan, $$$

Input: borough=Manhattan, max_price=3, categories=['Shows & Live Events'], toggles=[]  
Nearest cluster: **10 · Upscale shows & live events**  
Clusters used: 1 · matching places in catalog: 641 · deck size: 10 · all cards pass filters: yes

| # | place | type | price | rating | neighborhood | cluster |
|---|---|---|---|---|---|---|
| 1 | Pip's Island | Performing Arts Theater | $$$ | 4.9 (279) | Hell's Kitchen, Manhattan | 10 |
| 2 | Minskoff Theatre | Performing Arts Theater | $$$ | 4.8 (7,562) | Midtown-Times Square, Manhattan | 10 |
| 3 | Metropolitan Opera House | Opera House | $$$ | 4.8 (7,367) | Upper West Side-Lincoln Square, Manhattan | 10 |
| 4 | Winter Garden Theatre | Performing Arts Theater | $$$ | 4.8 (5,881) | Midtown-Times Square, Manhattan | 10 |
| 5 | The Barrow Group Performing Arts Center | Educational Institution | $$$ | 4.8 (261) | Midtown-Times Square, Manhattan | 10 |
| 6 | Madison Square Garden | Arena | $$$ | 4.7 (35,168) | Midtown South-Flatiron-Union Square, Manhattan | 10 |
| 7 | New York Philharmonic | Shows & Live Events | $$$ | 4.7 (462) | Upper West Side-Lincoln Square, Manhattan | 10 |
| 8 | Naumburg Bandshell | Live Music Venue | $$$ | 4.7 (434) | Central Park, Manhattan | 10 |
| 9 | Houghton Hall Arts Community | Shows & Live Events | $$$ | 5.0 (34) | Midtown South-Flatiron-Union Square, Manhattan | 10 |
| 10 | The Greene Space | Event Venue | $$$ | 4.7 (143) | SoHo-Little Italy-Hudson Square, Manhattan | 10 |

## Group games night, Brooklyn

Input: borough=Brooklyn, max_price=2, categories=['Games & Indoor Fun'], toggles=['groups']  
Nearest cluster: **21 · Mid-range games & indoor fun**  
Clusters used: 1 · matching places in catalog: 88 · deck size: 10 · all cards pass filters: yes

| # | place | type | price | rating | neighborhood | cluster |
|---|---|---|---|---|---|---|
| 1 | Beat The Bomb Brooklyn | Amusement Center | $$ | 5.0 (16,289) | Downtown Brooklyn-DUMBO-Boerum Hill, Brooklyn | 21 |
| 2 | The Escape Game Brooklyn | Amusement Center | $$ | 5.0 (4,931) | Downtown Brooklyn-DUMBO-Boerum Hill, Brooklyn | 21 |
| 3 | MyssTic Rooms | Amusement Center | $$ | 5.0 (1,209) | Park Slope, Brooklyn | 21 |
| 4 | Just Fun Events | Kids Parties & Events | Games & Indoor Fun | $$ | 5.0 (303) | Gravesend (East)-Homecrest, Brooklyn | 21 |
| 5 | CLOUD GAMING | LOUNGE | Internet Cafe | $$ | 5.0 (153) | Sheepshead Bay-Manhattan Beach-Gerritsen Beach, Brooklyn | 21 |
| 6 | Max Adventures Kids Birthday Party Place | Games & Indoor Fun | $$ | 4.8 (1,015) | Marine Park-Mill Basin-Bergen Beach, Brooklyn | 21 |
| 7 | Rainbow Playspace | Indoor Playground | $$ | 4.8 (1,013) | Sheepshead Bay-Manhattan Beach-Gerritsen Beach, Brooklyn | 21 |
| 8 | Max Funland | Video Arcade | $$ | 4.8 (943) | Bensonhurst, Brooklyn | 21 |
| 9 | Red Hook Pinball Museum | Video Arcade | $$ | 5.0 (85) | Carroll Gardens-Cobble Hill-Gowanus-Red Hook, Brooklyn | 21 |
| 10 | Rainbow Playspace & Arcade - Bensonhurst | Indoor Playground | $$ | 4.8 (433) | Bensonhurst, Brooklyn | 21 |

## Budget eats, Bronx, late

Input: borough=Bronx, max_price=1, categories=['Restaurants'], toggles=['nightlife']  
Nearest cluster: **14 · Mid-range restaurants · late-night, reservations**  
Clusters used: 3 · matching places in catalog: 1,458 · deck size: 10 · all cards pass filters: yes

| # | place | type | price | rating | neighborhood | cluster |
|---|---|---|---|---|---|---|
| 1 | empire express | Chinese Restaurant | $ | 4.8 (382) | Throgs Neck-Schuylerville, Bronx | 15 |
| 2 | Colima Taqueria | Mexican Restaurant | $ | 4.7 (1,819) | Belmont, Bronx | 15 |
| 3 | Taqueria Muñoz | Mexican Restaurant | $ | 4.8 (122) | Mount Eden-Claremont (West), Bronx | 15 |
| 4 | Hook & Reel Cajun Seafood & Bar | Seafood Restaurant | $ | 4.6 (1,283) | Concourse-Concourse Village, Bronx | 14 |
| 5 | Pugsley Pizza | Pizza Restaurant | $ | 4.6 (746) | Belmont, Bronx | 15 |
| 6 | Viva Cafe Mexican Restaurant | Mexican Restaurant | $ | 4.7 (89) | Mott Haven-Port Morris, Bronx | 15 |
| 7 | Morris Park Inn | American Restaurant | $ | 4.6 (221) | Morris Park, Bronx | 6 |
| 8 | India Passage | Indian Restaurant | $ | 4.8 (38) | Melrose, Bronx | 6 |
| 9 | Arthur Ave Crust & Kitchen | Pizza Restaurant | $ | 4.5 (462) | Belmont, Bronx | 15 |
| 10 | Country Bay Pizza | Restaurant | $ | 4.5 (79) | Pelham Bay-Country Club-City Island, Bronx | 14 |

## Dog-friendly outdoors, any borough

Input: borough=any, max_price=2, categories=['Parks & Outdoors', 'Cafes & Desserts'], toggles=['dogs', 'outdoors']  
Nearest cluster: **0 · Free parks & outdoors · outdoor, family-friendly**  
Clusters used: 3 · matching places in catalog: 9,204 · deck size: 10 · all cards pass filters: yes

| # | place | type | price | rating | neighborhood | cluster |
|---|---|---|---|---|---|---|
| 1 | 9/11 Memorial Pools | Park | Free | 4.9 (17,154) | Financial District-Battery Park City, Manhattan | 0 |
| 2 | 11:11 Cafe | Coffee Shop | $$ | 4.9 (339) | Williamsburg, Brooklyn | 3 |
| 3 | Ground Zero | Park | Free | 4.9 (1,940) | Financial District-Battery Park City, Manhattan | 0 |
| 4 | Busy Bee Coffee | Coffee Shop | $$ | 4.8 (1,354) | Flushing-Willets Point, Queens | 3 |
| 5 | Just Kidding Playground - Universe (South Shore) | Playground | Free | 4.9 (723) | Tottenville-Charleston, Staten Island | 0 |
| 6 | Tartinery Café - Bar | Greenwich Village | Cafe | $$ | 4.8 (1,328) | Greenwich Village, Manhattan | 3 |
| 7 | North Tower Pool | Park | Free | 4.9 (634) | Financial District-Battery Park City, Manhattan | 0 |
| 8 | GLORY DAYS | Coffee Shop | $$ | 4.9 (170) | Williamsburg, Brooklyn | 3 |
| 9 | Gantry Plaza State Park | State Park | Free | 4.8 (10,319) | Long Island City-Hunters Point, Queens | 0 |
| 10 | Honey Crepes (Regular, Vegan, Gluten- Free, Vegan/GF, Buckwheat Crepes) | Dessert Shop | $$ | 4.8 (181) | East Village, Manhattan | 3 |

## Tourist day, Manhattan, $$

Input: borough=Manhattan, max_price=2, categories=['Attractions & Tours', 'Museums & Galleries'], toggles=[]  
Nearest cluster: **5 · Mid-range attractions · family-friendly**  
Clusters used: 2 · matching places in catalog: 2,143 · deck size: 10 · all cards pass filters: yes

| # | place | type | price | rating | neighborhood | cluster |
|---|---|---|---|---|---|---|
| 1 | Immersive Gamebox - Essex Crossing, Lower East Side | Tourist Attraction | $$ | 4.9 (4,650) | Lower East Side, Manhattan | 5 |
| 2 | AUTOPHOTO | Photobooth Gallery & Museum | Services | $$ | 5.0 (1,919) | Lower East Side, Manhattan | 9 |
| 3 | athometrip | Travel Agency | $$ | 4.9 (1,458) | Midtown-Times Square, Manhattan | 5 |
| 4 | Play Street Museum - Upper West Side | Museum | $$ | 4.9 (512) | Upper West Side-Manhattan Valley, Manhattan | 9 |
| 5 | New York Pedicab Services | Tour Agency | $$ | 4.9 (514) | Midtown-Times Square, Manhattan | 5 |
| 6 | 9/11 Memorial & Museum | Museum | $$ | 4.8 (96,308) | Financial District-Battery Park City, Manhattan | 9 |
| 7 | Luminiscence New York | Tourist Attraction | $$ | 4.9 (411) | Midtown-Times Square, Manhattan | 5 |
| 8 | The Metropolitan Museum of Art | Art museum | $$ | 4.8 (95,584) | Central Park, Manhattan | 9 |
| 9 | Small Bus Tours NYC | Tour Agency | $$ | 4.9 (275) | Midtown-Times Square, Manhattan | 5 |
| 10 | The Met Cloisters | Art museum | $$ | 4.8 (9,266) | Washington Heights (North), Manhattan | 9 |

## Fine dining, Manhattan

Input: borough=Manhattan, max_price=4, categories=['Restaurants'], toggles=['groups']  
Nearest cluster: **18 · Luxury restaurants · drinks, reservations**  
Clusters used: 1 · matching places in catalog: 7,066 · deck size: 10 · all cards pass filters: yes

| # | place | type | price | rating | neighborhood | cluster |
|---|---|---|---|---|---|---|
| 1 | Osteria Carlina Tribeca | Italian Restaurant | $$$$ | 4.9 (1,273) | Tribeca-Civic Center, Manhattan | 18 |
| 2 | Atlantis Prime | Fine Dining Restaurant | $$$$ | 4.9 (758) | Midtown-Times Square, Manhattan | 18 |
| 3 | TAKUMI OMAKASE | Japanese Restaurant | $$$$ | 4.9 (1,960) | Lower East Side, Manhattan | 18 |
| 4 | STK Steakhouse | Steak House | $$$$ | 4.8 (40,309) | Midtown-Times Square, Manhattan | 18 |
| 5 | Club A Steakhouse | Steak House | $$$$ | 4.8 (3,904) | East Midtown-Turtle Bay, Manhattan | 18 |
| 6 | NIKU X | Wagyu BBQ & Seafood | Steak House | $$$$ | 4.8 (3,201) | Midtown-Times Square, Manhattan | 18 |
| 7 | Maison Close Restaurant | French Restaurant | $$$$ | 4.8 (2,597) | SoHo-Little Italy-Hudson Square, Manhattan | 18 |
| 8 | Ayah Restaurant | Moroccan Restaurant | $$$$ | 4.8 (2,399) | SoHo-Little Italy-Hudson Square, Manhattan | 18 |
| 9 | Barnea Bistro | Restaurant | $$$$ | 4.8 (1,838) | East Midtown-Turtle Bay, Manhattan | 18 |
| 10 | Mido Omakase - West Village | Sushi Restaurant | $$$$ | 4.9 (521) | Greenwich Village, Manhattan | 18 |
