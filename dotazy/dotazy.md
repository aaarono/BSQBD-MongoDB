docker compose exec router01 mongosh -u user -p pass --authenticationDatabase admin

===== Práce s daty =====

1) insertOne s writeConcern a kontrolou JSON schématu
Obecné chování:
  – vloží jeden dokument do kolekce;
  – před vložením zkontroluje dokument podle JSON schématu, definovaného ve validátoru kolekce;
  – vrací objekt s informací o provedeném vložení.
V konkrétním případě:
  – kolekce TopAnime má JSON validátor, který zajišťuje přítomnost povinných polí 
    (animeid, name, genres apod.) a jejich datové typy;
  – writeConcern:{ w:"majority", wtimeout:5000 } zaručuje, že zápis bude potvrzen většinou replik 
    do 5 sekund, jinak dojde k chybě.
> db.TopAnime.insertOne(
  {
    animeid:     100001,
    animeurl:    "https://myanimedb.org/anime/100001",
    imageurl:    "https://images.myanimedb.org/100001.jpg",
    name:        "Netrivialne Anime",
    englishname: null,
    genres:      "Action, Fantasy",
    synopsis:    "Popis...",
    type:        "TV",
    episodes:    24,
    premiered:   "Spring 2025",
    producers:   "Oleksandr",
    studios:     "UPCE",
    source:      "Light Novel",
    duration:    "24 min",
    rating:      "PG-13",
    rank:        500,
    popularity:  7500,
    score:       9.1,
    statistics: {
      scoredBy:  30000,
      members:   45000,
      favorites: 1200
    },
    tags: ["New", "Recommended"]
  },
  {
    writeConcern: { w: "majority", wtimeout: 5000 }
  }
);

2) insertMany s ordered:false a zpracováním chyb
Obecné chování:
  – vloží pole dokumentů;
  – ordered:true (výchozí): při první chybě přestane vkládat zbývající;
  – ordered:false: pokračuje ve vkládání všech dokumentů a sbírá chyby.
V konkrétním případě:
  – dokument s ID 99002 má prázdné pole Title – může selhat JSON validací;
  – třetímu dokumentu Title úplně chybí – také porušení schématu;
  – ordered:false umožní vložit 99001 a validní části z 99003;
  – chyby lze zachytit v catch(BulkWriteError) a zpracovat detaily.
> const newMovies = [
    { ID: 99001, Title: "Movie 43", Overview:"...", ReleaseDate:"2021-05-01", Popularity:6.5, VoteAverage:6.2, VoteCount:1200 },
    { ID: 99002, Title: "", Overview:"...", ReleaseDate:"2021-06-01", Popularity:7.1, VoteAverage:7.0, VoteCount: 800 },
    { ID: 99003, Overview:"...", ReleaseDate:"2021-07-01", Popularity:5.4, VoteAverage:5.0, VoteCount: 400 }
  ];
db.TopMovies.insertMany(newMovies, { ordered: false });

3) findOneAndUpdate s agregační pipeline a upsert
Obecné chování:
  – najde jeden dokument podle filtru a aktualizuje jej;
  – pipeline styl ($set, $add apod.) umožňuje počítat hodnoty za běhu;
  – upsert:true — pokud dokument neexistuje, vytvoří nový;
  – returnDocument:"after" — vrátí dokument po aktualizaci nebo vložení.
V konkrétním případě:
  – hledá se ShowID:"s8800";
  – pokud existuje ReleaseYear — přičte se 1; jinak se nastaví 2025;
  – pokud chybí Title — dosadí "Unknown Title";
  – nastaví lastModified na aktuální čas ($$NOW);
  – pokud dokument nebyl nalezen, vytvoří se nový se všemi těmito poli.
> db.TopNetflix.findOneAndUpdate(
  { ShowID: "s8800" },
  [
    {
      $set: {
        ReleaseYear: {
          $ifNull: [
            { $add: ["$ReleaseYear", 1] },
            2025
          ]
        },
        Title: { $ifNull: ["$Title", "Unknown Title"] },
        lastModified: "$$NOW"
      }
    }
  ],
  {
    upsert: true,
    returnDocument: "after"
  }
);

4) updateMany s agregační pipeline a collation
Obecné chování:
  – aktualizuje všechny dokumenty odpovídající filtru;
  – pipeline styl ($set) poskytuje flexibilní výpočty;
  – collation definuje pravidla porovnávání řetězců (lokalita, citlivost na velikost písmen/diakritiku).
V konkrétním případě:
  – vybírají se anime s score >= 9.0;
  – vytváří se nové pole scoreCategory:
      – pokud score >= 9.5 — "Outstanding", jinak — "Excellent";
  – collation:{locale:"en",strength:2} — anglická pravidla, ignoruje velikost písmen.
> db.TopAnime.updateMany(
    { score: { $gte: 9.0 } },
    [
      { $set: {
          scoreCategory: {
            $cond: {
              if: { $gte: ["$score", 9.5] },
              then: "Outstanding",
              else: "Excellent"
            }
          }
        }
      }
    ],
    {
      collation: { locale: "en", strength: 2 }
    }
);

5) findOneAndDelete s tříděním
Obecné chování:
  – find → sort → limit(1) → next() najde jeden dokument;
  – atomicky jej odstraní pomocí findOneAndDelete;
  – projekcí lze vrátit jen vybraná pole.
V konkrétním případě:
  – hledá film s VoteAverage < 6;
  – třídí podle VoteCount vzestupně, aby byl nejméně populární první;
  – pokud existuje, vypíše jeho údaje a odstraní, vrátí Title, VoteAverage, VoteCount;
  – jinak vypíše, že žádné takové filmy nejsou.
> var doc = db.TopMovies.find({ VoteAverage: { $lt: 6 } }).sort({ VoteCount: 1 }).limit(1).next();
if (doc) {
  print("Deleting:", doc.Title, "(ID:", doc.ID, ", Avg:", doc.VoteAverage, ", Count:", doc.VoteCount, ")");
  printjson(
    db.TopMovies.findOneAndDelete(
      { ID: doc.ID },
      { projection: { Title:1, VoteAverage:1, VoteCount:1 } }
    )
  );
} else {
  print("Films with VoteAverage < 6 not found");
};

6) deleteMany s writeConcern
Obecné chování:
  – smaže všechny dokumenty odpovídající filtru;
  – writeConcern:{ w:"majority", j:true } čeká:
      – na potvrzení většinou replik (w:"majority")
      – na zapsání do journalu (j:true).
V konkrétním případě:
  – smaže všechny záznamy v TopNetflix, kde ReleaseYear < 2000;
  – zajistí spolehlivý, zálohovaný záznam o smazání.
> db.TopNetflix.deleteMany(
    { ReleaseYear: { $lt: 2000 } },
    { writeConcern: { w: "majority", j: true } }
);

===== Agregační funkce =====

1) Průměrné skóre podle typu anime (TopAnime)
Obecné chování:
  – filtruje dokumenty podle podmínky ($match);
  – seskupuje je podle hodnoty pole ($group);
  – počítá agregované hodnoty ($avg, $sum);
  – vybírá pouze požadovaná pole ($project);
  – řadí výsledky podle průměrného skóre ($sort).
V konkrétním případě:
  – vybírá anime s score > 8;
  – seskupuje podle typu (TV, Movie atd.);
  – počítá avgScore (průměrné skóre) a count (počet anime);
  – ve výstupu místo _id ukazuje type, avgScore a count;
  – řadí podle avgScore sestupně.
> db.TopAnime.aggregate([
    { $match:   { score: { $gt: 8 } } },
    { $group:   { _id: "$type",
                  avgScore: { $avg: "$score" },
                  count:    { $sum: 1 } } },
    { $project: { _id: 0,
                  type:    "$_id",
                  avgScore:1,
                  count:   1 } },
    { $sort:    { avgScore: -1 } }
]);

2) Top-5 let podle počtu filmů (TopMovies)
Obecné chování:
  – vybírá dokumenty s existujícím polem ($match);
  – seskupuje podle roku získaného ze stringu ($group s $substr);
  – promítá pole year a total ($project);
  – řadí podle total ($sort);
  – omezuje výsledky na 5 záznamů ($limit).
V konkrétním případě:
  – bere filmy, kde ReleaseDate existuje;
  – ze stringu ReleaseDate bere prvních 4 znaků jako rok;
  – počítá počet filmů za každý rok;
  – ve výstupu ukazuje year a total;
  – vybírá pět let s nejvíce filmy.
> db.TopMovies.aggregate([
    { $match:   { ReleaseDate: { $exists: true } } },
    { $group:   { _id: { $substr: ["$ReleaseDate", 0, 4] },
                  total: { $sum: 1 } } },
    { $project: { _id: 0,
                  year:  "$_id",
                  total: 1 } },
    { $sort:    { total: -1 } },
    { $limit:   5 }
]);

3) Top-10 zemí podle počtu pořadů (TopNetflix)
Obecné chování:
  – filtruje dokumenty s platným polem country ($match);
  – přidává pole countries jako pole stringů ($addFields + $split);
  – „rozlévá“ každou zemi do samostatného dokumentu ($unwind);
  – seskupuje podle země ($group);
  – promítá fields country a total ($project);
  – řadí podle total sestupně a omezuje na 10 ($sort + $limit).
V konkrétním případě:
  – bere všechny záznamy, kde country není prázdné;
  – rozděluje text country podle „, “ na seznam států;
  – pro každý prvek seznamu počítá, kolik show z té země existuje;
  – ve výstupu ukazuje country a total;
  – vybírá 10 nejčastějších zemí.
> db.TopNetflix.aggregate([
    { $match: { country: { $exists: true, $ne: "" } } },
    { $addFields: {
        countries: { $split: ["$country", ", "] }
      }
    },
    { $unwind:  "$countries" },
    { $group:   { _id: "$countries", total: { $sum: 1 } } },
    { $project: { _id: 0, country: "$_id", total: 1 } },
    { $sort:    { total: -1 } },
    { $limit:   10 }
]);

4) Průměrná popularita anime podle žánrů (TopAnime)
Obecné chování:
  – filtruje anime podle popularity ($match);
  – vytváří pole genreList z textu ($addFields + $split);
  – „rozlévá“ každý žánr do samostatného dokumentu ($unwind);
  – seskupuje podle žánru s výpočtem průměru a počtu ($group);
  – promítá genre, avgPop a count ($project);
  – řadí podle avgPop sestupně ($sort).
V konkrétním případě:
  – bere jen anime, která mají popularity > 0;
  – dělí genres podle „, “ na jednotlivé žánry;
  – počítá průměrnou popularitu avgPop a počet anime count pro každý žánr;
  – ve výstupu ukazuje genre, avgPop, count;
  – řadí žánry podle avgPop sestupně.
> db.TopAnime.aggregate([
    { $match: { popularity: { $gt: 0 } } },
    { $addFields: {
        genreList: { $split: ["$genres", ", "] }
      }
    },
    { $unwind:  "$genreList" },
    { $group:   { _id: "$genreList",
                  avgPop: { $avg: "$popularity" },
                  count:  { $sum: 1 } } },
    { $project: { _id: 0, genre: "$_id", avgPop: 1, count: 1 } },
    { $sort:    { avgPop: -1 } }
]);

5) Top-3 filmy podle VoteCount po roce 2010 (TopMovies)
Obecné chování:
  – filtruje filmy podle ReleaseDate regexem ($match);
  – řadí podle VoteCount sestupně ($sort);
  – omezuje na 3 výsledky ($limit);
  – promítá vybraná pole ($project).
V konkrétním případě:
  – vybere filmy, jejichž ReleaseDate začíná na „2010–2020“;
  – seřadí je podle VoteCount od nejvyššího;
  – vybere první 3 položky;
  – ve výstupu ukáže ID, Title, VoteAverage a VoteCount.
> db.TopMovies.aggregate([
    { $match: { ReleaseDate: { $regex: "^20(1[0-9]|20)" } } },
    { $sort:  { VoteCount: -1 } },
    { $limit: 3 },
    { $project: { _id:0, ID:1, Title:1, VoteAverage:1, VoteCount:1 } }
]);

6) Vyhledávání filmů → anime adaptace (lookup mezi kolekcemi)
Obecné chování:
  – spojuje kolekce pomocí $lookup;
  – filtruje dokumenty, kde existuje alespoň jedno spojení ($match s exists);
  – uvnitř $project transformuje poli animeAdaptations pomocí $map;
  – omezuje počet výsledků ($limit).
V konkrétním případě:
  – pro každé TopMovies hledá shodu Title → name v TopAnime;
  – filtruje jen filmy, které mají alespoň jednu adaptaci;
  – ve výstupu pro každou adaptaci ukazuje animeid, animeScore a adaptationUrl;
  – omezuje výsledky na prvních 5 filmů s adaptacemi.
> db.TopMovies.aggregate([
    {
      $lookup: {
        from:         "TopAnime",
        localField:   "Title",
        foreignField: "name",
        as:           "animeAdaptations"
      }
    },
    { $match: { "animeAdaptations.0": { $exists: true } } },
    { $project: {
        _id: 0,
        Title: 1,
        animeAdaptations: {
          $map: {
            input: "$animeAdaptations",
            as:    "a",
            in: {
              animeid:       "$$a.animeid",
              animeScore:    "$$a.score",
              adaptationUrl: "$$a.animeurl"
            }
          }
        }
    } },
    { $limit: 5 }
]);

===== Konfigurace =====

1) Analýza rozložení chunků na shardy
Obecné chování:
  – používá kolekci config.chunks, kde MongoDB uchovává informace o jednotlivých čunkách;
  – agreguje dokumenty podle shardů ($group) a spočítá jejich počet;
  – promítá výsledky s označením shardů a počtem chunků ($project);
  – řadí podle počtu chunků sestupně ($sort).
V konkrétním případě:
  – přepneme se do databáze config, kde jsou metadáta o shardingové infrastruktuře;
  – spočítáme, kolik chunků je aktuálně na každém shardu;
  – výstupem je tabulka shard → chunkCount seřazená od nejvyššího počtu chunků.
> use config;
db.chunks.aggregate([
    { $group: {
        _id: "$shard", 
        chunkCount: { $sum: 1 }
      }
    },
    { $project: {
        _id: 0, 
        shard: "$_id", 
        chunkCount: 1
      }
    },
    { $sort: { chunkCount: -1 } }
]);

2) Přesun primárního shardu databáze (movePrimary)
Obecné chování:
  – administrativní příkaz movePrimary přenese primární část databáze na jiný shard;
  – aktualizuje metadata v config.databases;
  – změny se projeví v sh.status().
V konkrétním případě:
  – přepneme se do admin databáze pro spuštění příkazu;
  – přesuneme primární shard databáze MyDatabase na rs-shard-02;
  – ověříme stav shardingového clusteru pomocí sh.status();
  – v config.databases si ověříme, že pole primary pro MyDatabase bylo změněno.
> use admin;
db.adminCommand({ movePrimary: "MyDatabase", to: "rs-shard-02" });
sh.status();
use config;
db.databases.findOne({ _id: "MyDatabase" });

3) Tag-aware sharding (zónové shardování)
Obecné chování:
  – sh.addShardToZone přidá shard do zóny (tagu);
  – sh.updateZoneKeyRange definuje rozsah klíčů, který patří do určité zóny;
  – sh.status() pak zobrazuje, jaké rozsahy jsou k jakým zónám přiřazeny.
V konkrétním případě:
  – přiřadíme shard rs-shard-01 do zóny „Europe“;
  – pro kolekci MyDatabase.TopAnime nastavíme rozsah klíče animeid od MinKey() do NumberLong(50000);
  – tím zajistíme, že všechny dokumenty s animeid < 50000 budou ukládány na shard rs-shard-01;
  – v sekci Zones výstupu sh.status() uvidíme tento rozsah v zóně Europe.
> sh.addShardToZone("rs-shard-01", "Europe");
sh.updateZoneKeyRange(
    "MyDatabase.TopAnime",
    { animeid: MinKey() },
    { animeid: NumberLong(50000) },
    "Europe"
  );
sh.status();

4) Diagnostika pomalých operací pomocí currentOp
Obecné chování:
  – db.currentOp vrací seznam právě běžících operací na mongod/mongos;
  – lze filtrovat podle parametru active, doby běhu secs_running a přítomnosti typu příkazu.
V konkrétním případě:
  – přepneme se do admin databáze;
  – vyfiltrujeme jen aktivní operace (active: true), které běží déle než 10 sekund;
  – omezíme výstup na ty, které obsahují klauzuli aggregation (command.aggregate exists).
> use admin;
db.currentOp({
  active:     true,
  secs_running: { $gt: 10 },
  "command.aggregate": {
    $exists: true
  }
});

5) explain("executionStats") pro agregaci přes mongos
Obecné chování:
  – explain("executionStats") vrací detailní statistiky provedení dotazu;
  – včetně počtu přečtených indexů, dokumentů, fáze executingu atd.
V konkrétním případě:
  – přepneme se do MyDatabase;
  – spustíme explain nad TopMovies.aggregate s filtrem VoteAverage >= 8.0;
  – řadíme podle VoteCount sestupně, limitujeme top-5 a projektujeme vybraná pole;
  – výsledek explain ukáže, jak efektivně MongoDB zpracovalo tento pipeline.
> use MyDatabase;
db.TopMovies.explain("executionStats").aggregate([
  { $match:   { VoteAverage: { $gte: 8.0 } } },
  { $sort:    { VoteCount: -1 } },
  { $limit:   5 },
  { $project: { _id:0, ID:1, Title:1, VoteAverage:1, VoteCount:1 } }
]);

6) Statistika kolekce (collStats)
Obecné chování:
  – runCommand({ collStats }) vrací informace o velikosti kolekce, indexech, počtu dokumentů atd.;
  – parametr scale změří hodnoty (size, storageSize) v požadovaných jednotkách;
  – verbose: true přidá podrobnější statistiky.
V konkrétním případě:
  – přepneme se do MyDatabase;
  – požádáme o statistiku kolekce TopMovies, škálujeme do MiB (1024*1024);
  – verbose: true zobrazí detailní informace o indexech, paddingFactor a dalších datech.
> use MyDatabase;
db.runCommand({
    collStats: "TopMovies",
    scale: 1024*1024,
    verbose: true
  });

===== Nested (embedded) dokumenty =====

1) Top-5 anime podle počtu “favorites”
Obecné chování:
  – promítá vybraná pole ($project);
  – řadí dokumenty podle rostoucího či klesajícího pořadí (–1 = sestupně) ($sort);
  – omezuje počet výsledků na zadané množství ($limit).
V konkrétním případě:
  – promítá název anime a počet “favorites” ze vstupního pole statistics;
  – řadí anime podle počtu “favorites” sestupně;
  – vybírá pouze 5 nejvíce oblíbených anime.
> db.TopAnime.aggregate([
  { $project: {
      _id: 0,
      name: 1,
      "statistics.favorites": 1
  }},
  { $sort: { "statistics.favorites": -1 } },
  { $limit: 5 }
]);

2) Rozdělení anime do tří “popularity” kategorií podle počtu members
Obecné chování:
  – seskupuje dokumenty podle zpracované hodnoty ($group + $switch uvnitř _id);
  – počítá agregáty jako počet a průměr ($sum, $avg);
  – řadí výsledky podle zvoleného klíče ($sort);
  – promítá výstupní pole do čitelné podoby ($project).
V konkrétním případě:
  – kategorie “mega-popular” pro members ≥ 200 000, “popular” pro ≥ 30 000, jinak “normal”;
  – pro každou kategorii počítá počet anime a průměrné skóre;
  – řadí kategorie podle velikosti skupiny sestupně;
  – v konečném výstupu ukazuje název kategorie, count a avgScore.
> db.TopAnime.aggregate([
  {
    $group: {
      _id: {
        $switch: {
          branches: [
            { case: { $gte: ["$statistics.members", 200000] }, then: "mega-popular" },
            { case: { $gte: ["$statistics.members", 30000] }, then: "popular" }
          ],
          default: "normal"
        }
      },
      count: { $sum: 1 },
      avgScore: { $avg: "$score" }
    }
  },
  { $sort: { count: -1 } },
  {
    $project: {
      _id: 0,
      category: "$_id",
      count: 1,
      avgScore: 1
    }
  }
]);

3) Rozbalení objektu statistics do pole klíč–hodnota a spočítání počtu polí
Obecné chování:
  – promění objekt na pole klíč–hodnota ($objectToArray v $project);
  – rozbalí pole do jednotlivých dokumentů ($unwind);
  – seskupí všechny záznamy do jedné skupiny a spočítá celkový součet ($group + $sum).
V konkrétním případě:
  – převede pole statistics na docs s {k, v};
  – každý prvek pole reprezentuje jeden pár klíč/hodnota;
  – sečte, kolik takových párů ve všech anime dohromady existuje;
  – vrátí jedno číslo totalStatsFields.
> db.TopAnime.aggregate([
  { $project: {
      statsArray: { $objectToArray: "$statistics" }
  }},
  { $unwind: "$statsArray" },
  { $group: {
      _id: null,
      totalStatsFields: { $sum: 1 }
  }}
]);

4) Klasifikace anime podle “popularity” a následná agregace
Obecné chování:
  – přidává nové pole na základě podmínky ($addFields + $cond);
  – seskupuje podle nového pole ($group);
  – počítá agregáty ($sum, $avg);
  – řadí podle výsledného agregátu ($sort).
V konkrétním případě:
  – nastaví popularity = “High” pro members > 500 000, jinak “Low”;
  – seskupí anime podle této popularity;
  – pro každou skupinu spočítá počet a průměrné favorites;
  – řadí kategorie podle avgFavorites sestupně.
> db.TopAnime.aggregate([
  { $addFields: {
      popularity: {
        $cond: [
          { $gt: ["$statistics.members", 500000] },
          "High",
          "Low"
        ]
      }
  }},
  { $group: {
      _id: "$popularity",
      count:        { $sum: 1 },
      avgFavorites: { $avg: "$statistics.favorites" }
  }},
  { $sort: { avgFavorites: -1 } }
]);

5) Hledání “nejbližšího” anime podle počtu favorites pomocí self-lookup
Obecné chování:
  – duplikuje pole pro porovnání ($addFields);
  – v rámci jedné kolekce provádí $lookup s pipeline, využívající $expr ($match + $gt);
  – řadí potenciální shody a vezme první ($sort + $limit);
  – promítá výsledky a zanoří do pole $arrayElemAt.
V konkrétním případě:
  – do root dokumentu přidá favCount = statistics.favorites;
  – v lookup pipeline hledá anime s favorites > myFav, řadí vzestupně, bere 1 nejmenší vyšší;
  – ve výstupu ukáže originální name, statistics.favorites a objekt nextHigherFav;
  – pro přehled vybere jen prvních 5 dokumentů.
> db.TopAnime.aggregate([
  { $addFields: {
      favCount: "$statistics.favorites"
  }},
  { $lookup: {
      from: "TopAnime",
      let: { myFav: "$favCount" },
      pipeline: [
        { $match: {
            $expr: { $gt: ["$statistics.favorites", "$$myFav"] }
        }},
        { $sort: { "statistics.favorites": 1 } },
        { $limit: 1 },
        { $project: { _id:0, name:1, "statistics.favorites":1 } }
      ],
      as: "nextHigherFav"
  }},
  { $project: {
      _id: 0,
      name: 1,
      "statistics.favorites": 1,
      nextHigherFav: { $arrayElemAt: ["$nextHigherFav", 0] }
  }},
  { $limit: 5 }
]);

6) Statistika podle rozsahů počtu members pomocí $bucket
Obecné chování:
  – rozdělí dokumenty do předem definovaných intervalů ($bucket);
  – pro každý interval spočítá zadané výstupy ($sum, $avg);
  – default bucket pojmenuje ty mimo rozsahy;
  – výsledné intervaly lze dále řadit ($sort).
V konkrétním případě:
  – boundaries: [0,100k,200k,300k,400k,500k,Infinity], default “500k+”;
  – pro každý bucket spočítá count, avgFavorites a avgScore;
  – řadí intervaly podle avgFavorites sestupně.
> db.TopAnime.aggregate([
  {
    $bucket: {
      groupBy: "$statistics.members",
      boundaries: [0, 100000, 200000, 300000, 400000, 500000, Infinity],
      default: "500k+",
      output: {
        count:      { $sum: 1 },
        avgFavorites: { $avg: "$statistics.favorites" },
        avgScore:     { $avg: "$score" }
      }
    }
  },
  {
    $sort: { avgFavorites: -1 }
  }
]);

===== Indexy =====

1) Kompozitní index na TopAnime
Obecné chování:
  – createIndex vytvoří index nad více polí, umožňující efektivní filtrování, řazení i projekci;
  – find s hint vynutí použití konkrétního indexu, což zaručí předvídatelný výkon;
  – sort a limit pak pracují nad indexovanými poli bez dodatečného skenování kolekce.
V konkrétním případě:
  – index „TypeScoreMembersIdx“ pokrývá pole type (vzestupně), score (sestupně) a members (sestupně);
  – dotaz najde anime typu "TV" se skóre ≥ 8, promítne animeid, name, type, score a members;
  – vynutí použití indexu, seřadí výsledky podle members sestupně a vrátí prvních 10 záznamů.
> db.TopAnime.createIndex(
  { type: 1, score: -1, members: -1 },
  { name: "TypeScoreMembersIdx" }
);
db.TopAnime.find(
  {
    type:  "TV",
    score: { $gte: 8 }
  },
  {
    _id:    0,
    animeid: 1,
    name:   1,
    type:   1,
    score:  1,
    members:1
  }
).sort({ members: -1 }).hint("TypeScoreMembersIdx").limit(10).forEach(doc => printjson(doc));

2) Částečný (partial) index na TopMovies
Obecné chování:
  – createIndex s partialFilterExpression vytvoří index jen pro dokumenty splňující filtr;
  – dotazy, které splňují podmínku filtru, mohou využít menšího indexu;
  – find + hint dovede optimalizovat dotaz na nejnovější a populární filmy.
V konkrétním případě:
  – index „RecentPopByDateIdx“ pokrývá ReleaseDate (sestupně) a Popularity (sestupně) pouze pro Popularity ≥ 5;
  – dotaz vezme filmy od 1.1.2010 s Popularity ≥ 5, promítne Title, ReleaseDate a Popularity;
  – použije partial index, seřadí podle ReleaseDate a Popularity sestupně, a vrátí 5 nejnovějších.
> db.TopMovies.createIndex(
  { ReleaseDate: -1, Popularity: -1 },
  {
    name: "RecentPopByDateIdx",
    partialFilterExpression: { Popularity: { $gte: 5 } }
  }
);
db.TopMovies.find(
  {
    ReleaseDate: { $gte: "2010-01-01" },
    Popularity:  { $gte: 5 }
  },
  {
    _id:         0,
    Title:       1,
    ReleaseDate: 1,
    Popularity:  1
  }
).sort({ ReleaseDate: -1, Popularity: -1 }).hint("RecentPopByDateIdx").limit(5).forEach(doc => printjson(doc));

3) Plnotextový (text) index na TopNetflix
Obecné chování:
  – createIndex s typem "text" umožňuje full-textové vyhledávání nad zadanými poli;
  – dotaz $text s $search hledá v indexovaných textech, řadí podle relevance ($meta:"textScore");
  – kombinace sort podle textScore a dalších polí dává kvalitní výstup.
V konkrétním případě:
  – index „NetflixTextIdx“ pokrývá pole Title a Description s anglickou analyzou;
  – find s $text vyhledá frázi "murder mystery" a projekcí vrátí ShowID, Title, rating a skóre relevance;
  – výsledky seřadí podle relevance (textScore) a rating sestupně, omezí na 5.
> db.TopNetflix.createIndex(
  { Title: "text", Description: "text" },
  {
    name: "NetflixTextIdx",
    default_language: "english"
  }
);
db.TopNetflix.find(
  {
    $text: { $search: "murder mystery" }
  },
  {
    _id:    0,
    ShowID: 1,
    Title:  1,
    rating: 1,
    score:  { $meta: "textScore" }
  }
).sort({ score: { $meta: "textScore" }, rating: -1 }).limit(5).forEach(doc => printjson(doc));

4) Řídký (sparse) index na TopAnime
Obecné chování:
  – sparse:true indexuje pouze dokumenty, které mají dané pole;
  – dotazy kontrolující existenci pole mohou využít tohoto menšího indexu;
  – šetří místo, pokud pole není ve všech dokumentech.
V konkrétním případě:
  – index „FavoritesSparse“ mapuje jen dokumenty, kde statistics.favorites existuje;
  – dotaz najde anime s favorites ≥ 5000, promítne animeid, name a počet favorites;
  – použije sparse index, seřadí podle favorites sestupně a vrátí 10 nejlepších.
> db.TopAnime.createIndex(
  { "statistics.favorites": -1 },
  {
    name:   "FavoritesSparse",
    sparse: true
  }
);
db.TopAnime.find(
  {
    "statistics.favorites": { $exists: true, $gte: 5000 }
  },
  {
    _id: 0,
    animeid: 1,
    name: 1,
    "statistics.favorites": 1
  }
).sort({ "statistics.favorites": -1 }).hint("FavoritesSparse").limit(10).forEach(doc => printjson(doc));

5) Wildcard-index na TopAnime
Obecné chování:
  – createIndex s "$**":1 vytvoří index nad všemi poli v rámci objektu;
  – umožní rychlé vyhledávání či řazení podle libovolného podpole;
  – časté u schémat s proměnlivými poli.
V konkrétním případě:
  – index „StatsWildcardIdx“ pokryje všechna podpole objektu statistics;
  – dotaz najde anime s members ≥ 1 000 000, promítne animeid, name a members;
  – použije wildcard index, seřadí podle members sestupně a vrátí 10 záznamů.
> db.TopAnime.createIndex(
  { "statistics.$**": 1 },
  { name: "StatsWildcardIdx" }
);
db.TopAnime.find(
  { "statistics.members": { $gte: 1000000 } },
  { _id: 0, animeid: 1, name: 1, "statistics.members": 1 }
).sort({ "statistics.members": -1 }).hint("StatsWildcardIdx").limit(10).forEach(doc => printjson(doc));

6) Hashed-index na TopAnime
Obecné chování:
  – hashed index rozkládá hodnoty na hash, což rozprostře zápis a čtení rovnoměrně mezi shardy;
  – rovnoměrná distribuce vhodná pro shardované klíče s vysokou kardinalitou.
V konkrétním případě:
  – index „AnimeIdHashed“ je hashed na poli animeid;
  – dotaz hledá anime s animeid v poli sampleIds;
  – použije hashed index (hint implicitně animeid_hashed), omezí na 10 výsledků.
> db.TopAnime.createIndex(
  { animeid: "hashed" },
  { name: "AnimeIdHashed" }
);
const sampleIds = [101, 202, 303];
db.TopAnime.find(
  { animeid: { $in: sampleIds } },
  { _id: 0, animeid: 1, name: 1, members: 1 }
).hint("animeid_hashed").limit(10).forEach(doc => printjson(doc));

7) Wildcard-text index na TopMovies
Obecné chování:
  – createIndex s "$**":"text" indexuje všechny textová pole kolekce;
  – full-text vyhledávání lze použít na libovolná textová pole bez explicitního definování;
  – řazení podle relevance ($meta:"textScore") dává nejlepší shody.
V konkrétním případě:
  – index „AllTextWildcardIdx“ pokryje veškeré textové subpóle TopMovies;
  – dotaz $text hledá "crime movies", vrací Title, Overview, ReleaseDate a skóre relevance;
  – výsledky seřadí podle textScore a vrátí 10 nejrelevantnějších filmů.
> db.TopMovies.createIndex(
  { "$**": "text" },
  {
    name: "AllTextWildcardIdx",
    default_language: "english"
  }
);
db.TopMovies.find(
  { $text: { $search: "crime movies" } },
  {
    score:      { $meta: "textScore" },
    Title:      1,
    Overview:   1,
    ReleaseDate:1,
    _id:        0
  }
).sort({ score: { $meta: "textScore" } }).limit(10).forEach(doc => printjson(doc));
