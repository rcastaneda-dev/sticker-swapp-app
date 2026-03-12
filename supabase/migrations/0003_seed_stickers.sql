-- Seed 980 stickers: 20 stadiums (pages 1-3) + 48 teams × 20 stickers (pages 4-112)
--
-- Page budget: 3 stadium + 39 (13 teams × 3pp) + 70 (35 teams × 2pp) = 112
-- Sticker budget: 20 stadiums + 48 × (19 players + 1 legend) = 980

do $$
declare
  sn       int := 0;   -- sticker_number counter
  pg       int := 1;   -- current page
  pg_count int := 0;   -- stickers placed on current page
  max_pp   int;        -- max stickers per page for current section/team
  i        int;
  j        int;

  -- 48 teams: first 13 get 3 album pages (7-7-6), remaining 35 get 2 pages (10-10)
  teams text[] := array[
    -- 3-page teams (13): hosts + marquee nations
    'Argentina', 'Brazil', 'USA', 'Mexico', 'Canada',
    'Germany', 'Spain', 'France', 'England', 'Italy',
    'Portugal', 'Netherlands', 'Japan',
    -- 2-page teams (35)
    'Uruguay', 'Colombia', 'Ecuador', 'Paraguay',
    'Panama', 'Costa Rica', 'Jamaica',
    'Belgium', 'Croatia', 'Denmark', 'Switzerland',
    'Austria', 'Turkey', 'Ukraine', 'Serbia', 'Hungary',
    'South Korea', 'Australia', 'Saudi Arabia', 'Iran',
    'Iraq', 'Uzbekistan', 'Qatar', 'Indonesia',
    'Morocco', 'Senegal', 'Nigeria', 'Cameroon',
    'Egypt', 'Ivory Coast', 'Algeria', 'Mali',
    'Tunisia', 'New Zealand', 'Trinidad and Tobago'
  ];

  legends text[] := array[
    -- Matching teams array order
    'Diego Maradona', 'Pelé', 'Landon Donovan', 'Hugo Sánchez', 'Dwayne De Rosario',
    'Franz Beckenbauer', 'Andrés Iniesta', 'Zinedine Zidane', 'Bobby Moore', 'Paolo Maldini',
    'Eusébio', 'Johan Cruyff', 'Hidetoshi Nakata',
    'Enzo Francescoli', 'Carlos Valderrama', 'Alberto Spencer', 'José Luis Chilavert',
    'Román Torres', 'Paulo Wanchope', 'Luton Shelton',
    'Paul Van Himst', 'Davor Šuker', 'Michael Laudrup', 'Stéphane Chapuisat',
    'Hans Krankl', 'Hakan Şükür', 'Andriy Shevchenko', 'Dragan Stojković', 'Ferenc Puskás',
    'Park Ji-sung', 'Tim Cahill', 'Sami Al-Jaber', 'Ali Daei',
    'Ahmed Radhi', 'Mirjalol Qosimov', 'Almoez Ali', 'Bambang Pamungkas',
    'Mustapha Hadji', 'El Hadji Diouf', 'Jay-Jay Okocha', 'Roger Milla',
    'Mohamed Aboutrika', 'Didier Drogba', 'Rabah Madjer', 'Frédéric Kanouté',
    'Tarak Dhiab', 'Wynton Rufer', 'Dwight Yorke'
  ];

  stadiums text[] := array[
    -- USA (11)
    'MetLife Stadium, New Jersey',
    'SoFi Stadium, Los Angeles',
    'AT&T Stadium, Dallas',
    'Hard Rock Stadium, Miami',
    'NRG Stadium, Houston',
    'Mercedes-Benz Stadium, Atlanta',
    'Lumen Field, Seattle',
    'Levi''s Stadium, San Francisco',
    'Lincoln Financial Field, Philadelphia',
    'Arrowhead Stadium, Kansas City',
    'Gillette Stadium, Foxborough',
    -- Mexico (3)
    'Estadio Azteca, Mexico City',
    'Estadio BBVA, Monterrey',
    'Estadio Akron, Guadalajara',
    -- Canada (2)
    'BMO Field, Toronto',
    'BC Place, Vancouver',
    -- Special (4)
    'FIFA World Cup 2026 Logo',
    'FIFA World Cup 2026 Trophy',
    'Official Match Ball',
    'Tournament Mascot'
  ];

begin
  -----------------------------------------------------------------
  -- SECTION 1: Stadiums & specials — pages 1-3 (7 + 7 + 6)
  -----------------------------------------------------------------
  max_pp := 7;
  for i in 1..20 loop
    if pg_count >= max_pp then
      pg := pg + 1;
      pg_count := 0;
    end if;

    sn := sn + 1;
    insert into stickers (sticker_number, title, team, page, type)
    values (sn, stadiums[i], null, pg, 'stadium');
    pg_count := pg_count + 1;
  end loop;

  -----------------------------------------------------------------
  -- SECTION 2: Teams — pages 4-112
  -----------------------------------------------------------------
  pg := 4;

  for i in 1..48 loop
    pg_count := 0;

    -- First 13 teams → 3 pages (max 7/page), rest → 2 pages (max 10/page)
    if i <= 13 then
      max_pp := 7;
    else
      max_pp := 10;
    end if;

    -- 19 players
    for j in 1..19 loop
      if pg_count >= max_pp then
        pg := pg + 1;
        pg_count := 0;
      end if;

      sn := sn + 1;
      insert into stickers (sticker_number, title, team, page, type)
      values (sn, teams[i] || ' - Player ' || j, teams[i], pg, 'player');
      pg_count := pg_count + 1;
    end loop;

    -- 1 legend
    if pg_count >= max_pp then
      pg := pg + 1;
      pg_count := 0;
    end if;

    sn := sn + 1;
    insert into stickers (sticker_number, title, team, page, type)
    values (sn, legends[i], teams[i], pg, 'legend');
    pg_count := pg_count + 1;

    -- Next team always starts on a fresh page
    pg := pg + 1;
  end loop;

  -----------------------------------------------------------------
  -- Sanity checks (raise if anything is off)
  -----------------------------------------------------------------
  if sn <> 980 then
    raise exception 'Expected 980 stickers, got %', sn;
  end if;
  -- pg was incremented past the last used page, so last used = pg - 1
  if pg - 1 <> 112 then
    raise exception 'Expected 112 pages, got %', pg - 1;
  end if;
end $$;
