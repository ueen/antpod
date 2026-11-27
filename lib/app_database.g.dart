// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $PodcastsTable extends Podcasts with TableInfo<$PodcastsTable, Podcast> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PodcastsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _imageUrlMeta =
      const VerificationMeta('imageUrl');
  @override
  late final GeneratedColumn<String> imageUrl = GeneratedColumn<String>(
      'image_url', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _feedUrlMeta =
      const VerificationMeta('feedUrl');
  @override
  late final GeneratedColumn<String> feedUrl = GeneratedColumn<String>(
      'feed_url', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _authorMeta = const VerificationMeta('author');
  @override
  late final GeneratedColumn<String> author = GeneratedColumn<String>(
      'author', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _websiteMeta =
      const VerificationMeta('website');
  @override
  late final GeneratedColumn<String> website = GeneratedColumn<String>(
      'website', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _subscribedAtMeta =
      const VerificationMeta('subscribedAt');
  @override
  late final GeneratedColumn<DateTime> subscribedAt = GeneratedColumn<DateTime>(
      'subscribed_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _isSubscribedMeta =
      const VerificationMeta('isSubscribed');
  @override
  late final GeneratedColumn<bool> isSubscribed = GeneratedColumn<bool>(
      'is_subscribed', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("is_subscribed" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _syncPausedMeta =
      const VerificationMeta('syncPaused');
  @override
  late final GeneratedColumn<bool> syncPaused = GeneratedColumn<bool>(
      'sync_paused', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("sync_paused" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _feedEtagMeta =
      const VerificationMeta('feedEtag');
  @override
  late final GeneratedColumn<String> feedEtag = GeneratedColumn<String>(
      'feed_etag', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _feedLastModifiedMeta =
      const VerificationMeta('feedLastModified');
  @override
  late final GeneratedColumn<String> feedLastModified = GeneratedColumn<String>(
      'feed_last_modified', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _feedHashMeta =
      const VerificationMeta('feedHash');
  @override
  late final GeneratedColumn<String> feedHash = GeneratedColumn<String>(
      'feed_hash', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _feedFailuresMeta =
      const VerificationMeta('feedFailures');
  @override
  late final GeneratedColumn<int> feedFailures = GeneratedColumn<int>(
      'feed_failures', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        title,
        description,
        imageUrl,
        feedUrl,
        author,
        website,
        subscribedAt,
        isSubscribed,
        syncPaused,
        feedEtag,
        feedLastModified,
        feedHash,
        feedFailures
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'podcasts';
  @override
  VerificationContext validateIntegrity(Insertable<Podcast> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('image_url')) {
      context.handle(_imageUrlMeta,
          imageUrl.isAcceptableOrUnknown(data['image_url']!, _imageUrlMeta));
    } else if (isInserting) {
      context.missing(_imageUrlMeta);
    }
    if (data.containsKey('feed_url')) {
      context.handle(_feedUrlMeta,
          feedUrl.isAcceptableOrUnknown(data['feed_url']!, _feedUrlMeta));
    } else if (isInserting) {
      context.missing(_feedUrlMeta);
    }
    if (data.containsKey('author')) {
      context.handle(_authorMeta,
          author.isAcceptableOrUnknown(data['author']!, _authorMeta));
    } else if (isInserting) {
      context.missing(_authorMeta);
    }
    if (data.containsKey('website')) {
      context.handle(_websiteMeta,
          website.isAcceptableOrUnknown(data['website']!, _websiteMeta));
    }
    if (data.containsKey('subscribed_at')) {
      context.handle(
          _subscribedAtMeta,
          subscribedAt.isAcceptableOrUnknown(
              data['subscribed_at']!, _subscribedAtMeta));
    }
    if (data.containsKey('is_subscribed')) {
      context.handle(
          _isSubscribedMeta,
          isSubscribed.isAcceptableOrUnknown(
              data['is_subscribed']!, _isSubscribedMeta));
    }
    if (data.containsKey('sync_paused')) {
      context.handle(
          _syncPausedMeta,
          syncPaused.isAcceptableOrUnknown(
              data['sync_paused']!, _syncPausedMeta));
    }
    if (data.containsKey('feed_etag')) {
      context.handle(_feedEtagMeta,
          feedEtag.isAcceptableOrUnknown(data['feed_etag']!, _feedEtagMeta));
    }
    if (data.containsKey('feed_last_modified')) {
      context.handle(
          _feedLastModifiedMeta,
          feedLastModified.isAcceptableOrUnknown(
              data['feed_last_modified']!, _feedLastModifiedMeta));
    }
    if (data.containsKey('feed_hash')) {
      context.handle(_feedHashMeta,
          feedHash.isAcceptableOrUnknown(data['feed_hash']!, _feedHashMeta));
    }
    if (data.containsKey('feed_failures')) {
      context.handle(
          _feedFailuresMeta,
          feedFailures.isAcceptableOrUnknown(
              data['feed_failures']!, _feedFailuresMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Podcast map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Podcast(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description'])!,
      imageUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}image_url'])!,
      feedUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}feed_url'])!,
      author: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}author'])!,
      website: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}website']),
      subscribedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}subscribed_at'])!,
      isSubscribed: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_subscribed'])!,
      syncPaused: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}sync_paused'])!,
      feedEtag: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}feed_etag']),
      feedLastModified: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}feed_last_modified']),
      feedHash: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}feed_hash']),
      feedFailures: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}feed_failures'])!,
    );
  }

  @override
  $PodcastsTable createAlias(String alias) {
    return $PodcastsTable(attachedDatabase, alias);
  }
}

class Podcast extends DataClass implements Insertable<Podcast> {
  final String id;
  final String title;
  final String description;
  final String imageUrl;
  final String feedUrl;
  final String author;
  final String? website;
  final DateTime subscribedAt;

  /// true = active subscription; false = temporary preview (not yet subscribed)
  final bool isSubscribed;

  /// true = skip this feed during background auto-refresh (user manually paused sync)
  final bool syncPaused;

  /// The feed's ETag and Last-Modified from the refresh that last parsed it,
  /// sent back so an unchanged feed answers 304 Not Modified.
  final String? feedEtag;
  final String? feedLastModified;

  /// Hash of the feed body last parsed (PodcastService.fetchFeed): a server
  /// that ignores the headers above but sends the same feed isn't parsed again.
  final String? feedHash;

  /// Refreshes in a row where this feed failed while others loaded, so the
  /// device was online: the podcast's page says the feed isn't loading.
  final int feedFailures;
  const Podcast(
      {required this.id,
      required this.title,
      required this.description,
      required this.imageUrl,
      required this.feedUrl,
      required this.author,
      this.website,
      required this.subscribedAt,
      required this.isSubscribed,
      required this.syncPaused,
      this.feedEtag,
      this.feedLastModified,
      this.feedHash,
      required this.feedFailures});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['description'] = Variable<String>(description);
    map['image_url'] = Variable<String>(imageUrl);
    map['feed_url'] = Variable<String>(feedUrl);
    map['author'] = Variable<String>(author);
    if (!nullToAbsent || website != null) {
      map['website'] = Variable<String>(website);
    }
    map['subscribed_at'] = Variable<DateTime>(subscribedAt);
    map['is_subscribed'] = Variable<bool>(isSubscribed);
    map['sync_paused'] = Variable<bool>(syncPaused);
    if (!nullToAbsent || feedEtag != null) {
      map['feed_etag'] = Variable<String>(feedEtag);
    }
    if (!nullToAbsent || feedLastModified != null) {
      map['feed_last_modified'] = Variable<String>(feedLastModified);
    }
    if (!nullToAbsent || feedHash != null) {
      map['feed_hash'] = Variable<String>(feedHash);
    }
    map['feed_failures'] = Variable<int>(feedFailures);
    return map;
  }

  PodcastsCompanion toCompanion(bool nullToAbsent) {
    return PodcastsCompanion(
      id: Value(id),
      title: Value(title),
      description: Value(description),
      imageUrl: Value(imageUrl),
      feedUrl: Value(feedUrl),
      author: Value(author),
      website: website == null && nullToAbsent
          ? const Value.absent()
          : Value(website),
      subscribedAt: Value(subscribedAt),
      isSubscribed: Value(isSubscribed),
      syncPaused: Value(syncPaused),
      feedEtag: feedEtag == null && nullToAbsent
          ? const Value.absent()
          : Value(feedEtag),
      feedLastModified: feedLastModified == null && nullToAbsent
          ? const Value.absent()
          : Value(feedLastModified),
      feedHash: feedHash == null && nullToAbsent
          ? const Value.absent()
          : Value(feedHash),
      feedFailures: Value(feedFailures),
    );
  }

  factory Podcast.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Podcast(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String>(json['description']),
      imageUrl: serializer.fromJson<String>(json['imageUrl']),
      feedUrl: serializer.fromJson<String>(json['feedUrl']),
      author: serializer.fromJson<String>(json['author']),
      website: serializer.fromJson<String?>(json['website']),
      subscribedAt: serializer.fromJson<DateTime>(json['subscribedAt']),
      isSubscribed: serializer.fromJson<bool>(json['isSubscribed']),
      syncPaused: serializer.fromJson<bool>(json['syncPaused']),
      feedEtag: serializer.fromJson<String?>(json['feedEtag']),
      feedLastModified: serializer.fromJson<String?>(json['feedLastModified']),
      feedHash: serializer.fromJson<String?>(json['feedHash']),
      feedFailures: serializer.fromJson<int>(json['feedFailures']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String>(description),
      'imageUrl': serializer.toJson<String>(imageUrl),
      'feedUrl': serializer.toJson<String>(feedUrl),
      'author': serializer.toJson<String>(author),
      'website': serializer.toJson<String?>(website),
      'subscribedAt': serializer.toJson<DateTime>(subscribedAt),
      'isSubscribed': serializer.toJson<bool>(isSubscribed),
      'syncPaused': serializer.toJson<bool>(syncPaused),
      'feedEtag': serializer.toJson<String?>(feedEtag),
      'feedLastModified': serializer.toJson<String?>(feedLastModified),
      'feedHash': serializer.toJson<String?>(feedHash),
      'feedFailures': serializer.toJson<int>(feedFailures),
    };
  }

  Podcast copyWith(
          {String? id,
          String? title,
          String? description,
          String? imageUrl,
          String? feedUrl,
          String? author,
          Value<String?> website = const Value.absent(),
          DateTime? subscribedAt,
          bool? isSubscribed,
          bool? syncPaused,
          Value<String?> feedEtag = const Value.absent(),
          Value<String?> feedLastModified = const Value.absent(),
          Value<String?> feedHash = const Value.absent(),
          int? feedFailures}) =>
      Podcast(
        id: id ?? this.id,
        title: title ?? this.title,
        description: description ?? this.description,
        imageUrl: imageUrl ?? this.imageUrl,
        feedUrl: feedUrl ?? this.feedUrl,
        author: author ?? this.author,
        website: website.present ? website.value : this.website,
        subscribedAt: subscribedAt ?? this.subscribedAt,
        isSubscribed: isSubscribed ?? this.isSubscribed,
        syncPaused: syncPaused ?? this.syncPaused,
        feedEtag: feedEtag.present ? feedEtag.value : this.feedEtag,
        feedLastModified: feedLastModified.present
            ? feedLastModified.value
            : this.feedLastModified,
        feedHash: feedHash.present ? feedHash.value : this.feedHash,
        feedFailures: feedFailures ?? this.feedFailures,
      );
  Podcast copyWithCompanion(PodcastsCompanion data) {
    return Podcast(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      description:
          data.description.present ? data.description.value : this.description,
      imageUrl: data.imageUrl.present ? data.imageUrl.value : this.imageUrl,
      feedUrl: data.feedUrl.present ? data.feedUrl.value : this.feedUrl,
      author: data.author.present ? data.author.value : this.author,
      website: data.website.present ? data.website.value : this.website,
      subscribedAt: data.subscribedAt.present
          ? data.subscribedAt.value
          : this.subscribedAt,
      isSubscribed: data.isSubscribed.present
          ? data.isSubscribed.value
          : this.isSubscribed,
      syncPaused:
          data.syncPaused.present ? data.syncPaused.value : this.syncPaused,
      feedEtag: data.feedEtag.present ? data.feedEtag.value : this.feedEtag,
      feedLastModified: data.feedLastModified.present
          ? data.feedLastModified.value
          : this.feedLastModified,
      feedHash: data.feedHash.present ? data.feedHash.value : this.feedHash,
      feedFailures: data.feedFailures.present
          ? data.feedFailures.value
          : this.feedFailures,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Podcast(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('feedUrl: $feedUrl, ')
          ..write('author: $author, ')
          ..write('website: $website, ')
          ..write('subscribedAt: $subscribedAt, ')
          ..write('isSubscribed: $isSubscribed, ')
          ..write('syncPaused: $syncPaused, ')
          ..write('feedEtag: $feedEtag, ')
          ..write('feedLastModified: $feedLastModified, ')
          ..write('feedHash: $feedHash, ')
          ..write('feedFailures: $feedFailures')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      title,
      description,
      imageUrl,
      feedUrl,
      author,
      website,
      subscribedAt,
      isSubscribed,
      syncPaused,
      feedEtag,
      feedLastModified,
      feedHash,
      feedFailures);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Podcast &&
          other.id == this.id &&
          other.title == this.title &&
          other.description == this.description &&
          other.imageUrl == this.imageUrl &&
          other.feedUrl == this.feedUrl &&
          other.author == this.author &&
          other.website == this.website &&
          other.subscribedAt == this.subscribedAt &&
          other.isSubscribed == this.isSubscribed &&
          other.syncPaused == this.syncPaused &&
          other.feedEtag == this.feedEtag &&
          other.feedLastModified == this.feedLastModified &&
          other.feedHash == this.feedHash &&
          other.feedFailures == this.feedFailures);
}

class PodcastsCompanion extends UpdateCompanion<Podcast> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> description;
  final Value<String> imageUrl;
  final Value<String> feedUrl;
  final Value<String> author;
  final Value<String?> website;
  final Value<DateTime> subscribedAt;
  final Value<bool> isSubscribed;
  final Value<bool> syncPaused;
  final Value<String?> feedEtag;
  final Value<String?> feedLastModified;
  final Value<String?> feedHash;
  final Value<int> feedFailures;
  final Value<int> rowid;
  const PodcastsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.imageUrl = const Value.absent(),
    this.feedUrl = const Value.absent(),
    this.author = const Value.absent(),
    this.website = const Value.absent(),
    this.subscribedAt = const Value.absent(),
    this.isSubscribed = const Value.absent(),
    this.syncPaused = const Value.absent(),
    this.feedEtag = const Value.absent(),
    this.feedLastModified = const Value.absent(),
    this.feedHash = const Value.absent(),
    this.feedFailures = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PodcastsCompanion.insert({
    required String id,
    required String title,
    required String description,
    required String imageUrl,
    required String feedUrl,
    required String author,
    this.website = const Value.absent(),
    this.subscribedAt = const Value.absent(),
    this.isSubscribed = const Value.absent(),
    this.syncPaused = const Value.absent(),
    this.feedEtag = const Value.absent(),
    this.feedLastModified = const Value.absent(),
    this.feedHash = const Value.absent(),
    this.feedFailures = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        title = Value(title),
        description = Value(description),
        imageUrl = Value(imageUrl),
        feedUrl = Value(feedUrl),
        author = Value(author);
  static Insertable<Podcast> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? description,
    Expression<String>? imageUrl,
    Expression<String>? feedUrl,
    Expression<String>? author,
    Expression<String>? website,
    Expression<DateTime>? subscribedAt,
    Expression<bool>? isSubscribed,
    Expression<bool>? syncPaused,
    Expression<String>? feedEtag,
    Expression<String>? feedLastModified,
    Expression<String>? feedHash,
    Expression<int>? feedFailures,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (imageUrl != null) 'image_url': imageUrl,
      if (feedUrl != null) 'feed_url': feedUrl,
      if (author != null) 'author': author,
      if (website != null) 'website': website,
      if (subscribedAt != null) 'subscribed_at': subscribedAt,
      if (isSubscribed != null) 'is_subscribed': isSubscribed,
      if (syncPaused != null) 'sync_paused': syncPaused,
      if (feedEtag != null) 'feed_etag': feedEtag,
      if (feedLastModified != null) 'feed_last_modified': feedLastModified,
      if (feedHash != null) 'feed_hash': feedHash,
      if (feedFailures != null) 'feed_failures': feedFailures,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PodcastsCompanion copyWith(
      {Value<String>? id,
      Value<String>? title,
      Value<String>? description,
      Value<String>? imageUrl,
      Value<String>? feedUrl,
      Value<String>? author,
      Value<String?>? website,
      Value<DateTime>? subscribedAt,
      Value<bool>? isSubscribed,
      Value<bool>? syncPaused,
      Value<String?>? feedEtag,
      Value<String?>? feedLastModified,
      Value<String?>? feedHash,
      Value<int>? feedFailures,
      Value<int>? rowid}) {
    return PodcastsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      feedUrl: feedUrl ?? this.feedUrl,
      author: author ?? this.author,
      website: website ?? this.website,
      subscribedAt: subscribedAt ?? this.subscribedAt,
      isSubscribed: isSubscribed ?? this.isSubscribed,
      syncPaused: syncPaused ?? this.syncPaused,
      feedEtag: feedEtag ?? this.feedEtag,
      feedLastModified: feedLastModified ?? this.feedLastModified,
      feedHash: feedHash ?? this.feedHash,
      feedFailures: feedFailures ?? this.feedFailures,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (imageUrl.present) {
      map['image_url'] = Variable<String>(imageUrl.value);
    }
    if (feedUrl.present) {
      map['feed_url'] = Variable<String>(feedUrl.value);
    }
    if (author.present) {
      map['author'] = Variable<String>(author.value);
    }
    if (website.present) {
      map['website'] = Variable<String>(website.value);
    }
    if (subscribedAt.present) {
      map['subscribed_at'] = Variable<DateTime>(subscribedAt.value);
    }
    if (isSubscribed.present) {
      map['is_subscribed'] = Variable<bool>(isSubscribed.value);
    }
    if (syncPaused.present) {
      map['sync_paused'] = Variable<bool>(syncPaused.value);
    }
    if (feedEtag.present) {
      map['feed_etag'] = Variable<String>(feedEtag.value);
    }
    if (feedLastModified.present) {
      map['feed_last_modified'] = Variable<String>(feedLastModified.value);
    }
    if (feedHash.present) {
      map['feed_hash'] = Variable<String>(feedHash.value);
    }
    if (feedFailures.present) {
      map['feed_failures'] = Variable<int>(feedFailures.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PodcastsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('feedUrl: $feedUrl, ')
          ..write('author: $author, ')
          ..write('website: $website, ')
          ..write('subscribedAt: $subscribedAt, ')
          ..write('isSubscribed: $isSubscribed, ')
          ..write('syncPaused: $syncPaused, ')
          ..write('feedEtag: $feedEtag, ')
          ..write('feedLastModified: $feedLastModified, ')
          ..write('feedHash: $feedHash, ')
          ..write('feedFailures: $feedFailures, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EpisodesTable extends Episodes with TableInfo<$EpisodesTable, Episode> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EpisodesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _podcastIdMeta =
      const VerificationMeta('podcastId');
  @override
  late final GeneratedColumn<String> podcastId = GeneratedColumn<String>(
      'podcast_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _podcastTitleMeta =
      const VerificationMeta('podcastTitle');
  @override
  late final GeneratedColumn<String> podcastTitle = GeneratedColumn<String>(
      'podcast_title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _podcastImageUrlMeta =
      const VerificationMeta('podcastImageUrl');
  @override
  late final GeneratedColumn<String> podcastImageUrl = GeneratedColumn<String>(
      'podcast_image_url', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _imageUrlMeta =
      const VerificationMeta('imageUrl');
  @override
  late final GeneratedColumn<String> imageUrl = GeneratedColumn<String>(
      'image_url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _audioUrlMeta =
      const VerificationMeta('audioUrl');
  @override
  late final GeneratedColumn<String> audioUrl = GeneratedColumn<String>(
      'audio_url', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _durationSecondsMeta =
      const VerificationMeta('durationSeconds');
  @override
  late final GeneratedColumn<int> durationSeconds = GeneratedColumn<int>(
      'duration_seconds', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _publishDateMeta =
      const VerificationMeta('publishDate');
  @override
  late final GeneratedColumn<DateTime> publishDate = GeneratedColumn<DateTime>(
      'publish_date', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      clientDefault: DateTime.now);
  static const VerificationMeta _isDownloadedMeta =
      const VerificationMeta('isDownloaded');
  @override
  late final GeneratedColumn<bool> isDownloaded = GeneratedColumn<bool>(
      'is_downloaded', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("is_downloaded" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _localPathMeta =
      const VerificationMeta('localPath');
  @override
  late final GeneratedColumn<String> localPath = GeneratedColumn<String>(
      'local_path', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _downloadTaskIdMeta =
      const VerificationMeta('downloadTaskId');
  @override
  late final GeneratedColumn<String> downloadTaskId = GeneratedColumn<String>(
      'download_task_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _lastPositionMsMeta =
      const VerificationMeta('lastPositionMs');
  @override
  late final GeneratedColumn<int> lastPositionMs = GeneratedColumn<int>(
      'last_position_ms', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _playbackPositionSecondsMeta =
      const VerificationMeta('playbackPositionSeconds');
  @override
  late final GeneratedColumn<int> playbackPositionSeconds =
      GeneratedColumn<int>('playback_position_seconds', aliasedName, false,
          type: DriftSqlType.int,
          requiredDuringInsert: false,
          defaultValue: const Constant(0));
  static const VerificationMeta _isFinishedMeta =
      const VerificationMeta('isFinished');
  @override
  late final GeneratedColumn<bool> isFinished = GeneratedColumn<bool>(
      'is_finished', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_finished" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _isSubscribedMeta =
      const VerificationMeta('isSubscribed');
  @override
  late final GeneratedColumn<bool> isSubscribed = GeneratedColumn<bool>(
      'is_subscribed', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("is_subscribed" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _chaptersUrlMeta =
      const VerificationMeta('chaptersUrl');
  @override
  late final GeneratedColumn<String> chaptersUrl = GeneratedColumn<String>(
      'chapters_url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _lastPlayedMeta =
      const VerificationMeta('lastPlayed');
  @override
  late final GeneratedColumn<DateTime> lastPlayed = GeneratedColumn<DateTime>(
      'last_played', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _markedForDownloadMeta =
      const VerificationMeta('markedForDownload');
  @override
  late final GeneratedColumn<bool> markedForDownload = GeneratedColumn<bool>(
      'marked_for_download', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("marked_for_download" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _isFavoriteMeta =
      const VerificationMeta('isFavorite');
  @override
  late final GeneratedColumn<bool> isFavorite = GeneratedColumn<bool>(
      'is_favorite', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_favorite" IN (0, 1))'),
      defaultValue: const Constant(false));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        podcastId,
        podcastTitle,
        podcastImageUrl,
        imageUrl,
        title,
        description,
        audioUrl,
        durationSeconds,
        publishDate,
        isDownloaded,
        localPath,
        downloadTaskId,
        lastPositionMs,
        playbackPositionSeconds,
        isFinished,
        isSubscribed,
        chaptersUrl,
        lastPlayed,
        markedForDownload,
        isFavorite
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'episodes';
  @override
  VerificationContext validateIntegrity(Insertable<Episode> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('podcast_id')) {
      context.handle(_podcastIdMeta,
          podcastId.isAcceptableOrUnknown(data['podcast_id']!, _podcastIdMeta));
    } else if (isInserting) {
      context.missing(_podcastIdMeta);
    }
    if (data.containsKey('podcast_title')) {
      context.handle(
          _podcastTitleMeta,
          podcastTitle.isAcceptableOrUnknown(
              data['podcast_title']!, _podcastTitleMeta));
    } else if (isInserting) {
      context.missing(_podcastTitleMeta);
    }
    if (data.containsKey('podcast_image_url')) {
      context.handle(
          _podcastImageUrlMeta,
          podcastImageUrl.isAcceptableOrUnknown(
              data['podcast_image_url']!, _podcastImageUrlMeta));
    } else if (isInserting) {
      context.missing(_podcastImageUrlMeta);
    }
    if (data.containsKey('image_url')) {
      context.handle(_imageUrlMeta,
          imageUrl.isAcceptableOrUnknown(data['image_url']!, _imageUrlMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('audio_url')) {
      context.handle(_audioUrlMeta,
          audioUrl.isAcceptableOrUnknown(data['audio_url']!, _audioUrlMeta));
    } else if (isInserting) {
      context.missing(_audioUrlMeta);
    }
    if (data.containsKey('duration_seconds')) {
      context.handle(
          _durationSecondsMeta,
          durationSeconds.isAcceptableOrUnknown(
              data['duration_seconds']!, _durationSecondsMeta));
    }
    if (data.containsKey('publish_date')) {
      context.handle(
          _publishDateMeta,
          publishDate.isAcceptableOrUnknown(
              data['publish_date']!, _publishDateMeta));
    }
    if (data.containsKey('is_downloaded')) {
      context.handle(
          _isDownloadedMeta,
          isDownloaded.isAcceptableOrUnknown(
              data['is_downloaded']!, _isDownloadedMeta));
    }
    if (data.containsKey('local_path')) {
      context.handle(_localPathMeta,
          localPath.isAcceptableOrUnknown(data['local_path']!, _localPathMeta));
    }
    if (data.containsKey('download_task_id')) {
      context.handle(
          _downloadTaskIdMeta,
          downloadTaskId.isAcceptableOrUnknown(
              data['download_task_id']!, _downloadTaskIdMeta));
    }
    if (data.containsKey('last_position_ms')) {
      context.handle(
          _lastPositionMsMeta,
          lastPositionMs.isAcceptableOrUnknown(
              data['last_position_ms']!, _lastPositionMsMeta));
    }
    if (data.containsKey('playback_position_seconds')) {
      context.handle(
          _playbackPositionSecondsMeta,
          playbackPositionSeconds.isAcceptableOrUnknown(
              data['playback_position_seconds']!,
              _playbackPositionSecondsMeta));
    }
    if (data.containsKey('is_finished')) {
      context.handle(
          _isFinishedMeta,
          isFinished.isAcceptableOrUnknown(
              data['is_finished']!, _isFinishedMeta));
    }
    if (data.containsKey('is_subscribed')) {
      context.handle(
          _isSubscribedMeta,
          isSubscribed.isAcceptableOrUnknown(
              data['is_subscribed']!, _isSubscribedMeta));
    }
    if (data.containsKey('chapters_url')) {
      context.handle(
          _chaptersUrlMeta,
          chaptersUrl.isAcceptableOrUnknown(
              data['chapters_url']!, _chaptersUrlMeta));
    }
    if (data.containsKey('last_played')) {
      context.handle(
          _lastPlayedMeta,
          lastPlayed.isAcceptableOrUnknown(
              data['last_played']!, _lastPlayedMeta));
    }
    if (data.containsKey('marked_for_download')) {
      context.handle(
          _markedForDownloadMeta,
          markedForDownload.isAcceptableOrUnknown(
              data['marked_for_download']!, _markedForDownloadMeta));
    }
    if (data.containsKey('is_favorite')) {
      context.handle(
          _isFavoriteMeta,
          isFavorite.isAcceptableOrUnknown(
              data['is_favorite']!, _isFavoriteMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Episode map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Episode(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      podcastId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}podcast_id'])!,
      podcastTitle: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}podcast_title'])!,
      podcastImageUrl: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}podcast_image_url'])!,
      imageUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}image_url']),
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description'])!,
      audioUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}audio_url'])!,
      durationSeconds: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}duration_seconds'])!,
      publishDate: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}publish_date'])!,
      isDownloaded: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_downloaded'])!,
      localPath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}local_path']),
      downloadTaskId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}download_task_id']),
      lastPositionMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}last_position_ms'])!,
      playbackPositionSeconds: attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}playback_position_seconds'])!,
      isFinished: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_finished'])!,
      isSubscribed: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_subscribed'])!,
      chaptersUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}chapters_url']),
      lastPlayed: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}last_played']),
      markedForDownload: attachedDatabase.typeMapping.read(
          DriftSqlType.bool, data['${effectivePrefix}marked_for_download'])!,
      isFavorite: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_favorite'])!,
    );
  }

  @override
  $EpisodesTable createAlias(String alias) {
    return $EpisodesTable(attachedDatabase, alias);
  }
}

class Episode extends DataClass implements Insertable<Episode> {
  final String id;
  final String podcastId;
  final String podcastTitle;
  final String podcastImageUrl;

  /// The episode's own cover (its itunes:image), if the feed gives one.
  final String? imageUrl;
  final String title;
  final String description;
  final String audioUrl;
  final int durationSeconds;

  /// When the feed dates it; an undated item's first sighting (a feed's
  /// later refreshes leave it be, see PodcastService.fetchFeed).
  final DateTime publishDate;
  final bool isDownloaded;
  final String? localPath;
  final String? downloadTaskId;

  /// Resume position in milliseconds (high precision).
  /// 0 = never started.
  final int lastPositionMs;

  /// Derived convenience: position in full seconds (for display).
  /// Kept for backward compat with older code paths.
  final int playbackPositionSeconds;

  /// true once the episode has been played to completion
  /// (position >= 95 % of duration, or explicitly marked).
  final bool isFinished;

  /// true  = from a subscribed podcast
  /// false = temporary Discover episode (deleted after playback)
  final bool isSubscribed;

  /// Where the feed's chapters are: the podcast:chapters JSON file, or a
  /// data: URI of the same JSON made from inline Podlove chapters.
  final String? chaptersUrl;

  /// Timestamp of the most recent playback interaction.
  /// Null if the episode has never been played.
  final DateTime? lastPlayed;

  /// true = queued to download the next time WiFi is available.
  final bool markedForDownload;

  /// Marked as a favourite: kept, temp or not, until unmarked; its download
  /// isn't deleted once played.
  final bool isFavorite;
  const Episode(
      {required this.id,
      required this.podcastId,
      required this.podcastTitle,
      required this.podcastImageUrl,
      this.imageUrl,
      required this.title,
      required this.description,
      required this.audioUrl,
      required this.durationSeconds,
      required this.publishDate,
      required this.isDownloaded,
      this.localPath,
      this.downloadTaskId,
      required this.lastPositionMs,
      required this.playbackPositionSeconds,
      required this.isFinished,
      required this.isSubscribed,
      this.chaptersUrl,
      this.lastPlayed,
      required this.markedForDownload,
      required this.isFavorite});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['podcast_id'] = Variable<String>(podcastId);
    map['podcast_title'] = Variable<String>(podcastTitle);
    map['podcast_image_url'] = Variable<String>(podcastImageUrl);
    if (!nullToAbsent || imageUrl != null) {
      map['image_url'] = Variable<String>(imageUrl);
    }
    map['title'] = Variable<String>(title);
    map['description'] = Variable<String>(description);
    map['audio_url'] = Variable<String>(audioUrl);
    map['duration_seconds'] = Variable<int>(durationSeconds);
    map['publish_date'] = Variable<DateTime>(publishDate);
    map['is_downloaded'] = Variable<bool>(isDownloaded);
    if (!nullToAbsent || localPath != null) {
      map['local_path'] = Variable<String>(localPath);
    }
    if (!nullToAbsent || downloadTaskId != null) {
      map['download_task_id'] = Variable<String>(downloadTaskId);
    }
    map['last_position_ms'] = Variable<int>(lastPositionMs);
    map['playback_position_seconds'] = Variable<int>(playbackPositionSeconds);
    map['is_finished'] = Variable<bool>(isFinished);
    map['is_subscribed'] = Variable<bool>(isSubscribed);
    if (!nullToAbsent || chaptersUrl != null) {
      map['chapters_url'] = Variable<String>(chaptersUrl);
    }
    if (!nullToAbsent || lastPlayed != null) {
      map['last_played'] = Variable<DateTime>(lastPlayed);
    }
    map['marked_for_download'] = Variable<bool>(markedForDownload);
    map['is_favorite'] = Variable<bool>(isFavorite);
    return map;
  }

  EpisodesCompanion toCompanion(bool nullToAbsent) {
    return EpisodesCompanion(
      id: Value(id),
      podcastId: Value(podcastId),
      podcastTitle: Value(podcastTitle),
      podcastImageUrl: Value(podcastImageUrl),
      imageUrl: imageUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(imageUrl),
      title: Value(title),
      description: Value(description),
      audioUrl: Value(audioUrl),
      durationSeconds: Value(durationSeconds),
      publishDate: Value(publishDate),
      isDownloaded: Value(isDownloaded),
      localPath: localPath == null && nullToAbsent
          ? const Value.absent()
          : Value(localPath),
      downloadTaskId: downloadTaskId == null && nullToAbsent
          ? const Value.absent()
          : Value(downloadTaskId),
      lastPositionMs: Value(lastPositionMs),
      playbackPositionSeconds: Value(playbackPositionSeconds),
      isFinished: Value(isFinished),
      isSubscribed: Value(isSubscribed),
      chaptersUrl: chaptersUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(chaptersUrl),
      lastPlayed: lastPlayed == null && nullToAbsent
          ? const Value.absent()
          : Value(lastPlayed),
      markedForDownload: Value(markedForDownload),
      isFavorite: Value(isFavorite),
    );
  }

  factory Episode.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Episode(
      id: serializer.fromJson<String>(json['id']),
      podcastId: serializer.fromJson<String>(json['podcastId']),
      podcastTitle: serializer.fromJson<String>(json['podcastTitle']),
      podcastImageUrl: serializer.fromJson<String>(json['podcastImageUrl']),
      imageUrl: serializer.fromJson<String?>(json['imageUrl']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String>(json['description']),
      audioUrl: serializer.fromJson<String>(json['audioUrl']),
      durationSeconds: serializer.fromJson<int>(json['durationSeconds']),
      publishDate: serializer.fromJson<DateTime>(json['publishDate']),
      isDownloaded: serializer.fromJson<bool>(json['isDownloaded']),
      localPath: serializer.fromJson<String?>(json['localPath']),
      downloadTaskId: serializer.fromJson<String?>(json['downloadTaskId']),
      lastPositionMs: serializer.fromJson<int>(json['lastPositionMs']),
      playbackPositionSeconds:
          serializer.fromJson<int>(json['playbackPositionSeconds']),
      isFinished: serializer.fromJson<bool>(json['isFinished']),
      isSubscribed: serializer.fromJson<bool>(json['isSubscribed']),
      chaptersUrl: serializer.fromJson<String?>(json['chaptersUrl']),
      lastPlayed: serializer.fromJson<DateTime?>(json['lastPlayed']),
      markedForDownload: serializer.fromJson<bool>(json['markedForDownload']),
      isFavorite: serializer.fromJson<bool>(json['isFavorite']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'podcastId': serializer.toJson<String>(podcastId),
      'podcastTitle': serializer.toJson<String>(podcastTitle),
      'podcastImageUrl': serializer.toJson<String>(podcastImageUrl),
      'imageUrl': serializer.toJson<String?>(imageUrl),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String>(description),
      'audioUrl': serializer.toJson<String>(audioUrl),
      'durationSeconds': serializer.toJson<int>(durationSeconds),
      'publishDate': serializer.toJson<DateTime>(publishDate),
      'isDownloaded': serializer.toJson<bool>(isDownloaded),
      'localPath': serializer.toJson<String?>(localPath),
      'downloadTaskId': serializer.toJson<String?>(downloadTaskId),
      'lastPositionMs': serializer.toJson<int>(lastPositionMs),
      'playbackPositionSeconds':
          serializer.toJson<int>(playbackPositionSeconds),
      'isFinished': serializer.toJson<bool>(isFinished),
      'isSubscribed': serializer.toJson<bool>(isSubscribed),
      'chaptersUrl': serializer.toJson<String?>(chaptersUrl),
      'lastPlayed': serializer.toJson<DateTime?>(lastPlayed),
      'markedForDownload': serializer.toJson<bool>(markedForDownload),
      'isFavorite': serializer.toJson<bool>(isFavorite),
    };
  }

  Episode copyWith(
          {String? id,
          String? podcastId,
          String? podcastTitle,
          String? podcastImageUrl,
          Value<String?> imageUrl = const Value.absent(),
          String? title,
          String? description,
          String? audioUrl,
          int? durationSeconds,
          DateTime? publishDate,
          bool? isDownloaded,
          Value<String?> localPath = const Value.absent(),
          Value<String?> downloadTaskId = const Value.absent(),
          int? lastPositionMs,
          int? playbackPositionSeconds,
          bool? isFinished,
          bool? isSubscribed,
          Value<String?> chaptersUrl = const Value.absent(),
          Value<DateTime?> lastPlayed = const Value.absent(),
          bool? markedForDownload,
          bool? isFavorite}) =>
      Episode(
        id: id ?? this.id,
        podcastId: podcastId ?? this.podcastId,
        podcastTitle: podcastTitle ?? this.podcastTitle,
        podcastImageUrl: podcastImageUrl ?? this.podcastImageUrl,
        imageUrl: imageUrl.present ? imageUrl.value : this.imageUrl,
        title: title ?? this.title,
        description: description ?? this.description,
        audioUrl: audioUrl ?? this.audioUrl,
        durationSeconds: durationSeconds ?? this.durationSeconds,
        publishDate: publishDate ?? this.publishDate,
        isDownloaded: isDownloaded ?? this.isDownloaded,
        localPath: localPath.present ? localPath.value : this.localPath,
        downloadTaskId:
            downloadTaskId.present ? downloadTaskId.value : this.downloadTaskId,
        lastPositionMs: lastPositionMs ?? this.lastPositionMs,
        playbackPositionSeconds:
            playbackPositionSeconds ?? this.playbackPositionSeconds,
        isFinished: isFinished ?? this.isFinished,
        isSubscribed: isSubscribed ?? this.isSubscribed,
        chaptersUrl: chaptersUrl.present ? chaptersUrl.value : this.chaptersUrl,
        lastPlayed: lastPlayed.present ? lastPlayed.value : this.lastPlayed,
        markedForDownload: markedForDownload ?? this.markedForDownload,
        isFavorite: isFavorite ?? this.isFavorite,
      );
  Episode copyWithCompanion(EpisodesCompanion data) {
    return Episode(
      id: data.id.present ? data.id.value : this.id,
      podcastId: data.podcastId.present ? data.podcastId.value : this.podcastId,
      podcastTitle: data.podcastTitle.present
          ? data.podcastTitle.value
          : this.podcastTitle,
      podcastImageUrl: data.podcastImageUrl.present
          ? data.podcastImageUrl.value
          : this.podcastImageUrl,
      imageUrl: data.imageUrl.present ? data.imageUrl.value : this.imageUrl,
      title: data.title.present ? data.title.value : this.title,
      description:
          data.description.present ? data.description.value : this.description,
      audioUrl: data.audioUrl.present ? data.audioUrl.value : this.audioUrl,
      durationSeconds: data.durationSeconds.present
          ? data.durationSeconds.value
          : this.durationSeconds,
      publishDate:
          data.publishDate.present ? data.publishDate.value : this.publishDate,
      isDownloaded: data.isDownloaded.present
          ? data.isDownloaded.value
          : this.isDownloaded,
      localPath: data.localPath.present ? data.localPath.value : this.localPath,
      downloadTaskId: data.downloadTaskId.present
          ? data.downloadTaskId.value
          : this.downloadTaskId,
      lastPositionMs: data.lastPositionMs.present
          ? data.lastPositionMs.value
          : this.lastPositionMs,
      playbackPositionSeconds: data.playbackPositionSeconds.present
          ? data.playbackPositionSeconds.value
          : this.playbackPositionSeconds,
      isFinished:
          data.isFinished.present ? data.isFinished.value : this.isFinished,
      isSubscribed: data.isSubscribed.present
          ? data.isSubscribed.value
          : this.isSubscribed,
      chaptersUrl:
          data.chaptersUrl.present ? data.chaptersUrl.value : this.chaptersUrl,
      lastPlayed:
          data.lastPlayed.present ? data.lastPlayed.value : this.lastPlayed,
      markedForDownload: data.markedForDownload.present
          ? data.markedForDownload.value
          : this.markedForDownload,
      isFavorite:
          data.isFavorite.present ? data.isFavorite.value : this.isFavorite,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Episode(')
          ..write('id: $id, ')
          ..write('podcastId: $podcastId, ')
          ..write('podcastTitle: $podcastTitle, ')
          ..write('podcastImageUrl: $podcastImageUrl, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('audioUrl: $audioUrl, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('publishDate: $publishDate, ')
          ..write('isDownloaded: $isDownloaded, ')
          ..write('localPath: $localPath, ')
          ..write('downloadTaskId: $downloadTaskId, ')
          ..write('lastPositionMs: $lastPositionMs, ')
          ..write('playbackPositionSeconds: $playbackPositionSeconds, ')
          ..write('isFinished: $isFinished, ')
          ..write('isSubscribed: $isSubscribed, ')
          ..write('chaptersUrl: $chaptersUrl, ')
          ..write('lastPlayed: $lastPlayed, ')
          ..write('markedForDownload: $markedForDownload, ')
          ..write('isFavorite: $isFavorite')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
        id,
        podcastId,
        podcastTitle,
        podcastImageUrl,
        imageUrl,
        title,
        description,
        audioUrl,
        durationSeconds,
        publishDate,
        isDownloaded,
        localPath,
        downloadTaskId,
        lastPositionMs,
        playbackPositionSeconds,
        isFinished,
        isSubscribed,
        chaptersUrl,
        lastPlayed,
        markedForDownload,
        isFavorite
      ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Episode &&
          other.id == this.id &&
          other.podcastId == this.podcastId &&
          other.podcastTitle == this.podcastTitle &&
          other.podcastImageUrl == this.podcastImageUrl &&
          other.imageUrl == this.imageUrl &&
          other.title == this.title &&
          other.description == this.description &&
          other.audioUrl == this.audioUrl &&
          other.durationSeconds == this.durationSeconds &&
          other.publishDate == this.publishDate &&
          other.isDownloaded == this.isDownloaded &&
          other.localPath == this.localPath &&
          other.downloadTaskId == this.downloadTaskId &&
          other.lastPositionMs == this.lastPositionMs &&
          other.playbackPositionSeconds == this.playbackPositionSeconds &&
          other.isFinished == this.isFinished &&
          other.isSubscribed == this.isSubscribed &&
          other.chaptersUrl == this.chaptersUrl &&
          other.lastPlayed == this.lastPlayed &&
          other.markedForDownload == this.markedForDownload &&
          other.isFavorite == this.isFavorite);
}

class EpisodesCompanion extends UpdateCompanion<Episode> {
  final Value<String> id;
  final Value<String> podcastId;
  final Value<String> podcastTitle;
  final Value<String> podcastImageUrl;
  final Value<String?> imageUrl;
  final Value<String> title;
  final Value<String> description;
  final Value<String> audioUrl;
  final Value<int> durationSeconds;
  final Value<DateTime> publishDate;
  final Value<bool> isDownloaded;
  final Value<String?> localPath;
  final Value<String?> downloadTaskId;
  final Value<int> lastPositionMs;
  final Value<int> playbackPositionSeconds;
  final Value<bool> isFinished;
  final Value<bool> isSubscribed;
  final Value<String?> chaptersUrl;
  final Value<DateTime?> lastPlayed;
  final Value<bool> markedForDownload;
  final Value<bool> isFavorite;
  final Value<int> rowid;
  const EpisodesCompanion({
    this.id = const Value.absent(),
    this.podcastId = const Value.absent(),
    this.podcastTitle = const Value.absent(),
    this.podcastImageUrl = const Value.absent(),
    this.imageUrl = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.audioUrl = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.publishDate = const Value.absent(),
    this.isDownloaded = const Value.absent(),
    this.localPath = const Value.absent(),
    this.downloadTaskId = const Value.absent(),
    this.lastPositionMs = const Value.absent(),
    this.playbackPositionSeconds = const Value.absent(),
    this.isFinished = const Value.absent(),
    this.isSubscribed = const Value.absent(),
    this.chaptersUrl = const Value.absent(),
    this.lastPlayed = const Value.absent(),
    this.markedForDownload = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EpisodesCompanion.insert({
    required String id,
    required String podcastId,
    required String podcastTitle,
    required String podcastImageUrl,
    this.imageUrl = const Value.absent(),
    required String title,
    required String description,
    required String audioUrl,
    this.durationSeconds = const Value.absent(),
    this.publishDate = const Value.absent(),
    this.isDownloaded = const Value.absent(),
    this.localPath = const Value.absent(),
    this.downloadTaskId = const Value.absent(),
    this.lastPositionMs = const Value.absent(),
    this.playbackPositionSeconds = const Value.absent(),
    this.isFinished = const Value.absent(),
    this.isSubscribed = const Value.absent(),
    this.chaptersUrl = const Value.absent(),
    this.lastPlayed = const Value.absent(),
    this.markedForDownload = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        podcastId = Value(podcastId),
        podcastTitle = Value(podcastTitle),
        podcastImageUrl = Value(podcastImageUrl),
        title = Value(title),
        description = Value(description),
        audioUrl = Value(audioUrl);
  static Insertable<Episode> custom({
    Expression<String>? id,
    Expression<String>? podcastId,
    Expression<String>? podcastTitle,
    Expression<String>? podcastImageUrl,
    Expression<String>? imageUrl,
    Expression<String>? title,
    Expression<String>? description,
    Expression<String>? audioUrl,
    Expression<int>? durationSeconds,
    Expression<DateTime>? publishDate,
    Expression<bool>? isDownloaded,
    Expression<String>? localPath,
    Expression<String>? downloadTaskId,
    Expression<int>? lastPositionMs,
    Expression<int>? playbackPositionSeconds,
    Expression<bool>? isFinished,
    Expression<bool>? isSubscribed,
    Expression<String>? chaptersUrl,
    Expression<DateTime>? lastPlayed,
    Expression<bool>? markedForDownload,
    Expression<bool>? isFavorite,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (podcastId != null) 'podcast_id': podcastId,
      if (podcastTitle != null) 'podcast_title': podcastTitle,
      if (podcastImageUrl != null) 'podcast_image_url': podcastImageUrl,
      if (imageUrl != null) 'image_url': imageUrl,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (audioUrl != null) 'audio_url': audioUrl,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (publishDate != null) 'publish_date': publishDate,
      if (isDownloaded != null) 'is_downloaded': isDownloaded,
      if (localPath != null) 'local_path': localPath,
      if (downloadTaskId != null) 'download_task_id': downloadTaskId,
      if (lastPositionMs != null) 'last_position_ms': lastPositionMs,
      if (playbackPositionSeconds != null)
        'playback_position_seconds': playbackPositionSeconds,
      if (isFinished != null) 'is_finished': isFinished,
      if (isSubscribed != null) 'is_subscribed': isSubscribed,
      if (chaptersUrl != null) 'chapters_url': chaptersUrl,
      if (lastPlayed != null) 'last_played': lastPlayed,
      if (markedForDownload != null) 'marked_for_download': markedForDownload,
      if (isFavorite != null) 'is_favorite': isFavorite,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EpisodesCompanion copyWith(
      {Value<String>? id,
      Value<String>? podcastId,
      Value<String>? podcastTitle,
      Value<String>? podcastImageUrl,
      Value<String?>? imageUrl,
      Value<String>? title,
      Value<String>? description,
      Value<String>? audioUrl,
      Value<int>? durationSeconds,
      Value<DateTime>? publishDate,
      Value<bool>? isDownloaded,
      Value<String?>? localPath,
      Value<String?>? downloadTaskId,
      Value<int>? lastPositionMs,
      Value<int>? playbackPositionSeconds,
      Value<bool>? isFinished,
      Value<bool>? isSubscribed,
      Value<String?>? chaptersUrl,
      Value<DateTime?>? lastPlayed,
      Value<bool>? markedForDownload,
      Value<bool>? isFavorite,
      Value<int>? rowid}) {
    return EpisodesCompanion(
      id: id ?? this.id,
      podcastId: podcastId ?? this.podcastId,
      podcastTitle: podcastTitle ?? this.podcastTitle,
      podcastImageUrl: podcastImageUrl ?? this.podcastImageUrl,
      imageUrl: imageUrl ?? this.imageUrl,
      title: title ?? this.title,
      description: description ?? this.description,
      audioUrl: audioUrl ?? this.audioUrl,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      publishDate: publishDate ?? this.publishDate,
      isDownloaded: isDownloaded ?? this.isDownloaded,
      localPath: localPath ?? this.localPath,
      downloadTaskId: downloadTaskId ?? this.downloadTaskId,
      lastPositionMs: lastPositionMs ?? this.lastPositionMs,
      playbackPositionSeconds:
          playbackPositionSeconds ?? this.playbackPositionSeconds,
      isFinished: isFinished ?? this.isFinished,
      isSubscribed: isSubscribed ?? this.isSubscribed,
      chaptersUrl: chaptersUrl ?? this.chaptersUrl,
      lastPlayed: lastPlayed ?? this.lastPlayed,
      markedForDownload: markedForDownload ?? this.markedForDownload,
      isFavorite: isFavorite ?? this.isFavorite,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (podcastId.present) {
      map['podcast_id'] = Variable<String>(podcastId.value);
    }
    if (podcastTitle.present) {
      map['podcast_title'] = Variable<String>(podcastTitle.value);
    }
    if (podcastImageUrl.present) {
      map['podcast_image_url'] = Variable<String>(podcastImageUrl.value);
    }
    if (imageUrl.present) {
      map['image_url'] = Variable<String>(imageUrl.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (audioUrl.present) {
      map['audio_url'] = Variable<String>(audioUrl.value);
    }
    if (durationSeconds.present) {
      map['duration_seconds'] = Variable<int>(durationSeconds.value);
    }
    if (publishDate.present) {
      map['publish_date'] = Variable<DateTime>(publishDate.value);
    }
    if (isDownloaded.present) {
      map['is_downloaded'] = Variable<bool>(isDownloaded.value);
    }
    if (localPath.present) {
      map['local_path'] = Variable<String>(localPath.value);
    }
    if (downloadTaskId.present) {
      map['download_task_id'] = Variable<String>(downloadTaskId.value);
    }
    if (lastPositionMs.present) {
      map['last_position_ms'] = Variable<int>(lastPositionMs.value);
    }
    if (playbackPositionSeconds.present) {
      map['playback_position_seconds'] =
          Variable<int>(playbackPositionSeconds.value);
    }
    if (isFinished.present) {
      map['is_finished'] = Variable<bool>(isFinished.value);
    }
    if (isSubscribed.present) {
      map['is_subscribed'] = Variable<bool>(isSubscribed.value);
    }
    if (chaptersUrl.present) {
      map['chapters_url'] = Variable<String>(chaptersUrl.value);
    }
    if (lastPlayed.present) {
      map['last_played'] = Variable<DateTime>(lastPlayed.value);
    }
    if (markedForDownload.present) {
      map['marked_for_download'] = Variable<bool>(markedForDownload.value);
    }
    if (isFavorite.present) {
      map['is_favorite'] = Variable<bool>(isFavorite.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EpisodesCompanion(')
          ..write('id: $id, ')
          ..write('podcastId: $podcastId, ')
          ..write('podcastTitle: $podcastTitle, ')
          ..write('podcastImageUrl: $podcastImageUrl, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('audioUrl: $audioUrl, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('publishDate: $publishDate, ')
          ..write('isDownloaded: $isDownloaded, ')
          ..write('localPath: $localPath, ')
          ..write('downloadTaskId: $downloadTaskId, ')
          ..write('lastPositionMs: $lastPositionMs, ')
          ..write('playbackPositionSeconds: $playbackPositionSeconds, ')
          ..write('isFinished: $isFinished, ')
          ..write('isSubscribed: $isSubscribed, ')
          ..write('chaptersUrl: $chaptersUrl, ')
          ..write('lastPlayed: $lastPlayed, ')
          ..write('markedForDownload: $markedForDownload, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $PodcastsTable podcasts = $PodcastsTable(this);
  late final $EpisodesTable episodes = $EpisodesTable(this);
  late final Index episodesPodcastDate = Index('episodes_podcast_date',
      'CREATE INDEX episodes_podcast_date ON episodes (podcast_id, publish_date)');
  late final Index episodesPublishDate = Index('episodes_publish_date',
      'CREATE INDEX episodes_publish_date ON episodes (publish_date)');
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [podcasts, episodes, episodesPodcastDate, episodesPublishDate];
}

typedef $$PodcastsTableCreateCompanionBuilder = PodcastsCompanion Function({
  required String id,
  required String title,
  required String description,
  required String imageUrl,
  required String feedUrl,
  required String author,
  Value<String?> website,
  Value<DateTime> subscribedAt,
  Value<bool> isSubscribed,
  Value<bool> syncPaused,
  Value<String?> feedEtag,
  Value<String?> feedLastModified,
  Value<String?> feedHash,
  Value<int> feedFailures,
  Value<int> rowid,
});
typedef $$PodcastsTableUpdateCompanionBuilder = PodcastsCompanion Function({
  Value<String> id,
  Value<String> title,
  Value<String> description,
  Value<String> imageUrl,
  Value<String> feedUrl,
  Value<String> author,
  Value<String?> website,
  Value<DateTime> subscribedAt,
  Value<bool> isSubscribed,
  Value<bool> syncPaused,
  Value<String?> feedEtag,
  Value<String?> feedLastModified,
  Value<String?> feedHash,
  Value<int> feedFailures,
  Value<int> rowid,
});

class $$PodcastsTableFilterComposer
    extends Composer<_$AppDatabase, $PodcastsTable> {
  $$PodcastsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get imageUrl => $composableBuilder(
      column: $table.imageUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get feedUrl => $composableBuilder(
      column: $table.feedUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get author => $composableBuilder(
      column: $table.author, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get website => $composableBuilder(
      column: $table.website, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get subscribedAt => $composableBuilder(
      column: $table.subscribedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isSubscribed => $composableBuilder(
      column: $table.isSubscribed, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get syncPaused => $composableBuilder(
      column: $table.syncPaused, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get feedEtag => $composableBuilder(
      column: $table.feedEtag, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get feedLastModified => $composableBuilder(
      column: $table.feedLastModified,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get feedHash => $composableBuilder(
      column: $table.feedHash, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get feedFailures => $composableBuilder(
      column: $table.feedFailures, builder: (column) => ColumnFilters(column));
}

class $$PodcastsTableOrderingComposer
    extends Composer<_$AppDatabase, $PodcastsTable> {
  $$PodcastsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get imageUrl => $composableBuilder(
      column: $table.imageUrl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get feedUrl => $composableBuilder(
      column: $table.feedUrl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get author => $composableBuilder(
      column: $table.author, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get website => $composableBuilder(
      column: $table.website, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get subscribedAt => $composableBuilder(
      column: $table.subscribedAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isSubscribed => $composableBuilder(
      column: $table.isSubscribed,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get syncPaused => $composableBuilder(
      column: $table.syncPaused, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get feedEtag => $composableBuilder(
      column: $table.feedEtag, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get feedLastModified => $composableBuilder(
      column: $table.feedLastModified,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get feedHash => $composableBuilder(
      column: $table.feedHash, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get feedFailures => $composableBuilder(
      column: $table.feedFailures,
      builder: (column) => ColumnOrderings(column));
}

class $$PodcastsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PodcastsTable> {
  $$PodcastsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => column);

  GeneratedColumn<String> get imageUrl =>
      $composableBuilder(column: $table.imageUrl, builder: (column) => column);

  GeneratedColumn<String> get feedUrl =>
      $composableBuilder(column: $table.feedUrl, builder: (column) => column);

  GeneratedColumn<String> get author =>
      $composableBuilder(column: $table.author, builder: (column) => column);

  GeneratedColumn<String> get website =>
      $composableBuilder(column: $table.website, builder: (column) => column);

  GeneratedColumn<DateTime> get subscribedAt => $composableBuilder(
      column: $table.subscribedAt, builder: (column) => column);

  GeneratedColumn<bool> get isSubscribed => $composableBuilder(
      column: $table.isSubscribed, builder: (column) => column);

  GeneratedColumn<bool> get syncPaused => $composableBuilder(
      column: $table.syncPaused, builder: (column) => column);

  GeneratedColumn<String> get feedEtag =>
      $composableBuilder(column: $table.feedEtag, builder: (column) => column);

  GeneratedColumn<String> get feedLastModified => $composableBuilder(
      column: $table.feedLastModified, builder: (column) => column);

  GeneratedColumn<String> get feedHash =>
      $composableBuilder(column: $table.feedHash, builder: (column) => column);

  GeneratedColumn<int> get feedFailures => $composableBuilder(
      column: $table.feedFailures, builder: (column) => column);
}

class $$PodcastsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PodcastsTable,
    Podcast,
    $$PodcastsTableFilterComposer,
    $$PodcastsTableOrderingComposer,
    $$PodcastsTableAnnotationComposer,
    $$PodcastsTableCreateCompanionBuilder,
    $$PodcastsTableUpdateCompanionBuilder,
    (Podcast, BaseReferences<_$AppDatabase, $PodcastsTable, Podcast>),
    Podcast,
    PrefetchHooks Function()> {
  $$PodcastsTableTableManager(_$AppDatabase db, $PodcastsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PodcastsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PodcastsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PodcastsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String> description = const Value.absent(),
            Value<String> imageUrl = const Value.absent(),
            Value<String> feedUrl = const Value.absent(),
            Value<String> author = const Value.absent(),
            Value<String?> website = const Value.absent(),
            Value<DateTime> subscribedAt = const Value.absent(),
            Value<bool> isSubscribed = const Value.absent(),
            Value<bool> syncPaused = const Value.absent(),
            Value<String?> feedEtag = const Value.absent(),
            Value<String?> feedLastModified = const Value.absent(),
            Value<String?> feedHash = const Value.absent(),
            Value<int> feedFailures = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PodcastsCompanion(
            id: id,
            title: title,
            description: description,
            imageUrl: imageUrl,
            feedUrl: feedUrl,
            author: author,
            website: website,
            subscribedAt: subscribedAt,
            isSubscribed: isSubscribed,
            syncPaused: syncPaused,
            feedEtag: feedEtag,
            feedLastModified: feedLastModified,
            feedHash: feedHash,
            feedFailures: feedFailures,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String title,
            required String description,
            required String imageUrl,
            required String feedUrl,
            required String author,
            Value<String?> website = const Value.absent(),
            Value<DateTime> subscribedAt = const Value.absent(),
            Value<bool> isSubscribed = const Value.absent(),
            Value<bool> syncPaused = const Value.absent(),
            Value<String?> feedEtag = const Value.absent(),
            Value<String?> feedLastModified = const Value.absent(),
            Value<String?> feedHash = const Value.absent(),
            Value<int> feedFailures = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PodcastsCompanion.insert(
            id: id,
            title: title,
            description: description,
            imageUrl: imageUrl,
            feedUrl: feedUrl,
            author: author,
            website: website,
            subscribedAt: subscribedAt,
            isSubscribed: isSubscribed,
            syncPaused: syncPaused,
            feedEtag: feedEtag,
            feedLastModified: feedLastModified,
            feedHash: feedHash,
            feedFailures: feedFailures,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$PodcastsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $PodcastsTable,
    Podcast,
    $$PodcastsTableFilterComposer,
    $$PodcastsTableOrderingComposer,
    $$PodcastsTableAnnotationComposer,
    $$PodcastsTableCreateCompanionBuilder,
    $$PodcastsTableUpdateCompanionBuilder,
    (Podcast, BaseReferences<_$AppDatabase, $PodcastsTable, Podcast>),
    Podcast,
    PrefetchHooks Function()>;
typedef $$EpisodesTableCreateCompanionBuilder = EpisodesCompanion Function({
  required String id,
  required String podcastId,
  required String podcastTitle,
  required String podcastImageUrl,
  Value<String?> imageUrl,
  required String title,
  required String description,
  required String audioUrl,
  Value<int> durationSeconds,
  Value<DateTime> publishDate,
  Value<bool> isDownloaded,
  Value<String?> localPath,
  Value<String?> downloadTaskId,
  Value<int> lastPositionMs,
  Value<int> playbackPositionSeconds,
  Value<bool> isFinished,
  Value<bool> isSubscribed,
  Value<String?> chaptersUrl,
  Value<DateTime?> lastPlayed,
  Value<bool> markedForDownload,
  Value<bool> isFavorite,
  Value<int> rowid,
});
typedef $$EpisodesTableUpdateCompanionBuilder = EpisodesCompanion Function({
  Value<String> id,
  Value<String> podcastId,
  Value<String> podcastTitle,
  Value<String> podcastImageUrl,
  Value<String?> imageUrl,
  Value<String> title,
  Value<String> description,
  Value<String> audioUrl,
  Value<int> durationSeconds,
  Value<DateTime> publishDate,
  Value<bool> isDownloaded,
  Value<String?> localPath,
  Value<String?> downloadTaskId,
  Value<int> lastPositionMs,
  Value<int> playbackPositionSeconds,
  Value<bool> isFinished,
  Value<bool> isSubscribed,
  Value<String?> chaptersUrl,
  Value<DateTime?> lastPlayed,
  Value<bool> markedForDownload,
  Value<bool> isFavorite,
  Value<int> rowid,
});

class $$EpisodesTableFilterComposer
    extends Composer<_$AppDatabase, $EpisodesTable> {
  $$EpisodesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get podcastId => $composableBuilder(
      column: $table.podcastId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get podcastTitle => $composableBuilder(
      column: $table.podcastTitle, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get podcastImageUrl => $composableBuilder(
      column: $table.podcastImageUrl,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get imageUrl => $composableBuilder(
      column: $table.imageUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get audioUrl => $composableBuilder(
      column: $table.audioUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get durationSeconds => $composableBuilder(
      column: $table.durationSeconds,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get publishDate => $composableBuilder(
      column: $table.publishDate, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isDownloaded => $composableBuilder(
      column: $table.isDownloaded, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get localPath => $composableBuilder(
      column: $table.localPath, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get downloadTaskId => $composableBuilder(
      column: $table.downloadTaskId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastPositionMs => $composableBuilder(
      column: $table.lastPositionMs,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get playbackPositionSeconds => $composableBuilder(
      column: $table.playbackPositionSeconds,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isFinished => $composableBuilder(
      column: $table.isFinished, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isSubscribed => $composableBuilder(
      column: $table.isSubscribed, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get chaptersUrl => $composableBuilder(
      column: $table.chaptersUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastPlayed => $composableBuilder(
      column: $table.lastPlayed, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get markedForDownload => $composableBuilder(
      column: $table.markedForDownload,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isFavorite => $composableBuilder(
      column: $table.isFavorite, builder: (column) => ColumnFilters(column));
}

class $$EpisodesTableOrderingComposer
    extends Composer<_$AppDatabase, $EpisodesTable> {
  $$EpisodesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get podcastId => $composableBuilder(
      column: $table.podcastId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get podcastTitle => $composableBuilder(
      column: $table.podcastTitle,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get podcastImageUrl => $composableBuilder(
      column: $table.podcastImageUrl,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get imageUrl => $composableBuilder(
      column: $table.imageUrl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get audioUrl => $composableBuilder(
      column: $table.audioUrl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get durationSeconds => $composableBuilder(
      column: $table.durationSeconds,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get publishDate => $composableBuilder(
      column: $table.publishDate, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isDownloaded => $composableBuilder(
      column: $table.isDownloaded,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get localPath => $composableBuilder(
      column: $table.localPath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get downloadTaskId => $composableBuilder(
      column: $table.downloadTaskId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastPositionMs => $composableBuilder(
      column: $table.lastPositionMs,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get playbackPositionSeconds => $composableBuilder(
      column: $table.playbackPositionSeconds,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isFinished => $composableBuilder(
      column: $table.isFinished, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isSubscribed => $composableBuilder(
      column: $table.isSubscribed,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get chaptersUrl => $composableBuilder(
      column: $table.chaptersUrl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastPlayed => $composableBuilder(
      column: $table.lastPlayed, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get markedForDownload => $composableBuilder(
      column: $table.markedForDownload,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isFavorite => $composableBuilder(
      column: $table.isFavorite, builder: (column) => ColumnOrderings(column));
}

class $$EpisodesTableAnnotationComposer
    extends Composer<_$AppDatabase, $EpisodesTable> {
  $$EpisodesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get podcastId =>
      $composableBuilder(column: $table.podcastId, builder: (column) => column);

  GeneratedColumn<String> get podcastTitle => $composableBuilder(
      column: $table.podcastTitle, builder: (column) => column);

  GeneratedColumn<String> get podcastImageUrl => $composableBuilder(
      column: $table.podcastImageUrl, builder: (column) => column);

  GeneratedColumn<String> get imageUrl =>
      $composableBuilder(column: $table.imageUrl, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => column);

  GeneratedColumn<String> get audioUrl =>
      $composableBuilder(column: $table.audioUrl, builder: (column) => column);

  GeneratedColumn<int> get durationSeconds => $composableBuilder(
      column: $table.durationSeconds, builder: (column) => column);

  GeneratedColumn<DateTime> get publishDate => $composableBuilder(
      column: $table.publishDate, builder: (column) => column);

  GeneratedColumn<bool> get isDownloaded => $composableBuilder(
      column: $table.isDownloaded, builder: (column) => column);

  GeneratedColumn<String> get localPath =>
      $composableBuilder(column: $table.localPath, builder: (column) => column);

  GeneratedColumn<String> get downloadTaskId => $composableBuilder(
      column: $table.downloadTaskId, builder: (column) => column);

  GeneratedColumn<int> get lastPositionMs => $composableBuilder(
      column: $table.lastPositionMs, builder: (column) => column);

  GeneratedColumn<int> get playbackPositionSeconds => $composableBuilder(
      column: $table.playbackPositionSeconds, builder: (column) => column);

  GeneratedColumn<bool> get isFinished => $composableBuilder(
      column: $table.isFinished, builder: (column) => column);

  GeneratedColumn<bool> get isSubscribed => $composableBuilder(
      column: $table.isSubscribed, builder: (column) => column);

  GeneratedColumn<String> get chaptersUrl => $composableBuilder(
      column: $table.chaptersUrl, builder: (column) => column);

  GeneratedColumn<DateTime> get lastPlayed => $composableBuilder(
      column: $table.lastPlayed, builder: (column) => column);

  GeneratedColumn<bool> get markedForDownload => $composableBuilder(
      column: $table.markedForDownload, builder: (column) => column);

  GeneratedColumn<bool> get isFavorite => $composableBuilder(
      column: $table.isFavorite, builder: (column) => column);
}

class $$EpisodesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $EpisodesTable,
    Episode,
    $$EpisodesTableFilterComposer,
    $$EpisodesTableOrderingComposer,
    $$EpisodesTableAnnotationComposer,
    $$EpisodesTableCreateCompanionBuilder,
    $$EpisodesTableUpdateCompanionBuilder,
    (Episode, BaseReferences<_$AppDatabase, $EpisodesTable, Episode>),
    Episode,
    PrefetchHooks Function()> {
  $$EpisodesTableTableManager(_$AppDatabase db, $EpisodesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EpisodesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EpisodesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EpisodesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> podcastId = const Value.absent(),
            Value<String> podcastTitle = const Value.absent(),
            Value<String> podcastImageUrl = const Value.absent(),
            Value<String?> imageUrl = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String> description = const Value.absent(),
            Value<String> audioUrl = const Value.absent(),
            Value<int> durationSeconds = const Value.absent(),
            Value<DateTime> publishDate = const Value.absent(),
            Value<bool> isDownloaded = const Value.absent(),
            Value<String?> localPath = const Value.absent(),
            Value<String?> downloadTaskId = const Value.absent(),
            Value<int> lastPositionMs = const Value.absent(),
            Value<int> playbackPositionSeconds = const Value.absent(),
            Value<bool> isFinished = const Value.absent(),
            Value<bool> isSubscribed = const Value.absent(),
            Value<String?> chaptersUrl = const Value.absent(),
            Value<DateTime?> lastPlayed = const Value.absent(),
            Value<bool> markedForDownload = const Value.absent(),
            Value<bool> isFavorite = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              EpisodesCompanion(
            id: id,
            podcastId: podcastId,
            podcastTitle: podcastTitle,
            podcastImageUrl: podcastImageUrl,
            imageUrl: imageUrl,
            title: title,
            description: description,
            audioUrl: audioUrl,
            durationSeconds: durationSeconds,
            publishDate: publishDate,
            isDownloaded: isDownloaded,
            localPath: localPath,
            downloadTaskId: downloadTaskId,
            lastPositionMs: lastPositionMs,
            playbackPositionSeconds: playbackPositionSeconds,
            isFinished: isFinished,
            isSubscribed: isSubscribed,
            chaptersUrl: chaptersUrl,
            lastPlayed: lastPlayed,
            markedForDownload: markedForDownload,
            isFavorite: isFavorite,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String podcastId,
            required String podcastTitle,
            required String podcastImageUrl,
            Value<String?> imageUrl = const Value.absent(),
            required String title,
            required String description,
            required String audioUrl,
            Value<int> durationSeconds = const Value.absent(),
            Value<DateTime> publishDate = const Value.absent(),
            Value<bool> isDownloaded = const Value.absent(),
            Value<String?> localPath = const Value.absent(),
            Value<String?> downloadTaskId = const Value.absent(),
            Value<int> lastPositionMs = const Value.absent(),
            Value<int> playbackPositionSeconds = const Value.absent(),
            Value<bool> isFinished = const Value.absent(),
            Value<bool> isSubscribed = const Value.absent(),
            Value<String?> chaptersUrl = const Value.absent(),
            Value<DateTime?> lastPlayed = const Value.absent(),
            Value<bool> markedForDownload = const Value.absent(),
            Value<bool> isFavorite = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              EpisodesCompanion.insert(
            id: id,
            podcastId: podcastId,
            podcastTitle: podcastTitle,
            podcastImageUrl: podcastImageUrl,
            imageUrl: imageUrl,
            title: title,
            description: description,
            audioUrl: audioUrl,
            durationSeconds: durationSeconds,
            publishDate: publishDate,
            isDownloaded: isDownloaded,
            localPath: localPath,
            downloadTaskId: downloadTaskId,
            lastPositionMs: lastPositionMs,
            playbackPositionSeconds: playbackPositionSeconds,
            isFinished: isFinished,
            isSubscribed: isSubscribed,
            chaptersUrl: chaptersUrl,
            lastPlayed: lastPlayed,
            markedForDownload: markedForDownload,
            isFavorite: isFavorite,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$EpisodesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $EpisodesTable,
    Episode,
    $$EpisodesTableFilterComposer,
    $$EpisodesTableOrderingComposer,
    $$EpisodesTableAnnotationComposer,
    $$EpisodesTableCreateCompanionBuilder,
    $$EpisodesTableUpdateCompanionBuilder,
    (Episode, BaseReferences<_$AppDatabase, $EpisodesTable, Episode>),
    Episode,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$PodcastsTableTableManager get podcasts =>
      $$PodcastsTableTableManager(_db, _db.podcasts);
  $$EpisodesTableTableManager get episodes =>
      $$EpisodesTableTableManager(_db, _db.episodes);
}
