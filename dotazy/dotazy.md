docker compose exec router01 mongosh -u user -p pass --authenticationDatabase admin

===== Práce s daty =====

1) insertOne с writeConcern и проверкой JSON-Schema
> db.TopAnime.insertOne(
    {
      animeid: 100001,
      animeurl:  "https://myanimedb.org/anime/100001",
      imageurl:  "https://images.myanimedb.org/100001.jpg",
      name:      "Netrivialne Anime",
      englishname: null,
      genres:    "Action, Fantasy",
      synopsis:  "Popis...",
      type:      "TV",
      episodes:  24,
      premiered: "Spring 2025",
      producers: "Oleksandr",
      studios:   "UPCE",
      source:    "Light Novel",
      duration:  "24 min",
      rating:    "PG-13",
      rank:      500,
      popularity:7500,
      favorites: 1200,
      scoredby:  30000,
      score:     9.1,
      members:   45000,
      tags:      ["New","Recommended"]
    },
    {
      writeConcern: { w: "majority", wtimeout: 5000 }
    }
)

2) insertMany с ordered:false и обработкой ошибок
> const newMovies = [
    { ID: 99001, Title: "Movie 43", Overview:"...", ReleaseDate:"2021-05-01", Popularity:6.5, VoteAverage:6.2, VoteCount:1200 },
    { ID: 99002, Title: "",        Overview:"...", ReleaseDate:"2021-06-01", Popularity:7.1, VoteAverage:7.0, VoteCount: 800 },
    { ID: 99003,                Overview:"...", ReleaseDate:"2021-07-01", Popularity:5.4, VoteAverage:5.0, VoteCount: 400 }
  ];
> db.TopMovies.insertMany(newMovies, { ordered: false })

3) findOneAndUpdate с aggregation-pipeline и upsert
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
)

4) updateMany с aggregation-pipeline и collation
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
)

5) findOneAndDelete с сортировкой
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
}

6) deleteMany с writeConcern
> db.TopNetflix.deleteMany(
    { ReleaseYear: { $lt: 2000 } },
    { writeConcern: { w: "majority", j: true } }
)

===== Agregační funkce =====

1) Средний score по типу аниме (TopAnime)
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

2) Топ-5 годов по числу фильмов (TopMovies)
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

3) Топ-10 стран по числу шоу (TopNetflix)
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

4) Средняя «популярность» аниме по жанрам (TopAnime)
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

5) Топ-3 фильмов по VoteCount после 2010-го (TopMovies)
> db.TopMovies.aggregate([
    { $match: { ReleaseDate: { $regex: "^20(1[0-9]|20)" } } },
    { $sort:  { VoteCount: -1 } },
    { $limit: 3 },
    { $project: { _id:0, ID:1, Title:1, VoteAverage:1, VoteCount:1 } }
]);

6) Поиск фильмов → аниме-адаптации (lookup между коллекциями)
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

1) Анализ распределения чанков по шардам
> use config
> db.chunks.aggregate([
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
])

2) Перенос primary-шара для базы (movePrimary)
> use admin
> db.adminCommand({ movePrimary: "MyDatabase", to: "rs-shard-02" })
> sh.status()
> use config
> db.databases.findOne({ _id: "MyDatabase" })

3) Tag-aware sharding (зоны)
> sh.addShardToZone("rs-shard-01", "Europe")
> sh.updateZoneKeyRange(
    "MyDatabase.TopAnime",
    { animeid: MinKey() },             // минимальная граница hashed-ключа
    { animeid: NumberLong(50000) },    // теперь — NumberLong, а не JS-число
    "Europe"
  )
> sh.status()
// В секции Zones видим диапазон animeid<50000 привязанный к Europe

4) Диагностика «тормозящих» операций через currentOp
> use admin
> db.currentOp({
  active:     true,          // только активные операции
  secs_running: { $gt: 10 }, // дольше 10 секунд
  "command.aggregate": {     // например, только aggregation-запросы
    $exists: true
  }
})

5) explain("executionStats") для агрегирования через mongos
> use MyDatabase
db.TopMovies.explain("executionStats").aggregate([
  { $match:   { VoteAverage: { $gte: 8.0 } } },     // только «хорошие» фильмы
  { $sort:    { VoteCount: -1 } },                 // по убыванию числа голосов
  { $limit:   5 },                                 // топ-5
  { $project: { _id:0, ID:1, Title:1, VoteAverage:1, VoteCount:1 } }
])

6) Статистика коллекции (collStats)
> use MyDatabase
> db.runCommand({
    collStats: "TopMovies",
    scale: 1024*1024,
    verbose: true
  })

===== Nested (embedded) dokumenty =====

0) Oбновить каждый документ, чтобы собрать три плоских поля (scoredby, members, favorites)
> db.TopAnime.updateMany(
  {},
  [
    { $set: {
        statistics: {
          scoredBy: "$scoredby",
          members:  "$members",
          favorites:"$favorites"
        }
    }},
    { $unset: ["scoredby","members","favorites"] }
  ]
);

1) Топ-5 аниме по «избранным»
> db.TopAnime.aggregate([
  { $project: {
      _id: 0,
      name: 1,
      "statistics.favorites": 1
  }},
  { $sort: { "statistics.favorites": -1 } },
  { $limit: 5 }
]);

2) Pазобьём аниме на три «уровня популярности» по полю members
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

3) Распаковка вложенного документа в массив ключ-значение и подсчёт полей
> db.TopAnime.aggregate([
  // Преобразуем объект statistics в массив {k, v}
  { $project: {
      statsArray: { $objectToArray: "$statistics" }
  }},
  // «Разворачиваем» массив на отдельные документы
  { $unwind: "$statsArray" },
  // Считаем общее число пар ключ-значение
  { $group: {
      _id: null,
      totalStatsFields: { $sum: 1 }
  }}
]);

4) Классификация аниме по «популярности» и группировка
> db.TopAnime.aggregate([
  // Добавляем новое поле popularity на основе числа members
  { $addFields: {
      popularity: {
        $cond: [
          { $gt: ["$statistics.members", 500000] },
          "High",   // если > 500k
          "Low"     // иначе
        ]
      }
  }},
  // Группируем по только что вычисленному полю
  { $group: {
      _id: "$popularity",
      count:        { $sum: 1 },
      avgFavorites: { $avg: "$statistics.favorites" }
  }},
  // Сортируем результат по среднему числу favorites
  { $sort: { avgFavorites: -1 } }
]);

5) Поиск ближайшего аниме по количеству favorites с помощью $lookup
> db.TopAnime.aggregate([
  // 1 Для удобства дублируем вложенное поле в корень
  { $addFields: {
      favCount: "$statistics.favorites"
  }},
  // 2 Self-lookup: ищем одно другое аниме с большим числом favorites,
  //    сортируем по возрастанию и берём первый — «ближайший» сверху
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
  // 3 Проекция: выводим имя, текущее число favorites и ближайшего соседа
  { $project: {
      _id: 0,
      name: 1,
      "statistics.favorites": 1,
      nextHigherFav: { $arrayElemAt: ["$nextHigherFav", 0] }
  }},
  // 4 Для примера возьмём только 5 документов
  { $limit: 5 }
]);

6) Статистика по группам участников с помощью $bucket
> db.TopAnime.aggregate([
  // 1 Разбиваем по диапазонам числа участников
  {
    $bucket: {
      groupBy: "$statistics.members",
      boundaries: [0, 100000, 200000, 300000, 400000, 500000, Infinity],
      default: "500k+",
      output: {
        count:      { $sum: 1              }, // число аниме в интервале
        avgFavorites: { $avg: "$statistics.favorites" },
        avgScore:     { $avg: "$score"     }
      }
    }
  },
  // 2 Сортируем интервалы по убыванию средней популярности (avgFavorites)
  {
    $sort: { avgFavorites: -1 }
  }
]);

===== Indexy =====

1) Композитный индекс на TopAnime
> db.TopAnime.createIndex(
  { type: 1, score: -1, members: -1 },
  { name: "TypeScoreMembersIdx" }
);
> db.TopAnime.find(
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

2) Частичный индекс на TopMovies
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

3) Полнотекстовый индекс на TopNetflix
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

4) Разреженный (sparse) индекс на TopAnime
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

5) Wildcard-индекс на TopAnime
> db.TopAnime.createIndex(
  { "statistics.$**": 1 },
  { name: "StatsWildcardIdx" }
);
db.TopAnime.find(
  { "statistics.members": { $gte: 1000000 } },
  { _id: 0, animeid: 1, name: 1, "statistics.members": 1 }
).sort({ "statistics.members": -1 }).hint("StatsWildcardIdx").limit(10).forEach(doc => printjson(doc));

6) Hashed-индекс на TopAnime
> db.TopAnime.createIndex(
  { animeid: "hashed" },
  { name: "AnimeIdHashed" }
);
const sampleIds = [101, 202, 303];
db.TopAnime.find(
  { animeid: { $in: sampleIds } },
  { _id: 0, animeid: 1, name: 1, members: 1 }
).hint("animeid_hashed").limit(10).forEach(doc => printjson(doc));

7) Wildcard-индекс на TopMovies
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
