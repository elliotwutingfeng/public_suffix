/*
 * Copyright 2019 Jakob Hjelm (Komposten)
 *
 * This file is part of public_suffix.
 *
 * public_suffix is a free Dart library: you can use, redistribute it and/or modify
 * it under the terms of the MIT license as written in the LICENSE file in the root
 * of this project.
 */

import 'package:punycode/punycode.dart';

import 'public_suffix_list.dart';

class PublicSuffix {
  final Uri sourceUri;

  bool _sourcePunycoded = false;
  String _rootDomain;
  String _publicTld;
  String _registrableDomain;

  PublicSuffix _punyDecoded;

  String get registrableDomain => _registrableDomain;

  String get rootDomain => _rootDomain;

  String get publicTld => _publicTld;

  /// Returns a punycode decoded version of this.
  PublicSuffix get punyDecoded => _punyDecoded;

  PublicSuffix._(this.sourceUri, this._rootDomain, this._publicTld) {
    _registrableDomain = "$_rootDomain.$_publicTld";
  }

  /// Creates a new instance based on the specified [sourceUri].
  ///
  /// Throws a [StateError] if [PublicSuffixList] has not been initialised.
  ///
  /// Throws an [ArgumentError] if [sourceUri] is missing the authority component
  /// (e.g. if no protocol is specified).
  PublicSuffix(this.sourceUri) {
    if (!PublicSuffixList.hasInitialised()) {
      throw StateError("PublicSuffixList has not been initialised!");
    }
    if (!sourceUri.hasAuthority) {
      throw ArgumentError(
          "The URI is missing the authority component: $sourceUri");
    }

    _parseUri(sourceUri, PublicSuffixList.suffixList);
  }

  void _parseUri(Uri uri, List<String> suffixList) {
    var host = _decodeHost(uri);
    var matchingRules = _findMatchingRules(host, suffixList);
    var prevailingRule = _getPrevailingRule(matchingRules);

    if (prevailingRule.startsWith('!')) {
      prevailingRule = _trimExceptionRule(prevailingRule);
    }

    _publicTld = _getPublicSuffix(host, prevailingRule);
    _rootDomain = _getDomainRoot(host, _publicTld);
    _punyDecoded = PublicSuffix._(sourceUri, _rootDomain, _publicTld);

    if (_sourcePunycoded) {
      _publicTld = _punyEncode(_publicTld);
      _rootDomain = _punyEncode(_rootDomain);
    }

    if (_rootDomain.isNotEmpty) {
      _registrableDomain = "$_rootDomain.$_publicTld";
    }
  }

  String _decodeHost(Uri uri) {
    var host = uri.host.replaceAll(RegExp(r'\.+$'), '').toLowerCase();
    host = Uri.decodeComponent(host);

    var punycodes = RegExp(r'xn--[a-z0-9-]+').allMatches(host);

    if (punycodes.isNotEmpty) {
      _sourcePunycoded = true;
      int offset = 0;
      punycodes.forEach((match) {
        var decoded = punycodeDecode(match.group(0).substring(4));
        host = host.replaceRange(
            match.start - offset, match.end - offset, decoded);
        offset += (match.end - match.start) - decoded.length;
      });
    }

    return host;
  }

  _findMatchingRules(String host, List<String> suffixList) {
    var matches = <String>[];

    for (var rule in suffixList) {
      if (_ruleMatches(rule, host)) {
        matches.add(rule);
      }
    }

    return matches;
  }

  bool _ruleMatches(String rule, String host) {
    var hostParts = host.split(".");
    var ruleParts = rule.split(".");

    hostParts.removeWhere((e) => e.isEmpty);

    var matches = true;

    if (ruleParts.length <= hostParts.length) {
      int r = ruleParts.length - 1;
      int h = hostParts.length - 1;

      while (r >= 0) {
        var rulePart = ruleParts[r];
        var hostPart = hostParts[h];

        if (rulePart != '*' &&
            rulePart != hostPart &&
            rulePart != "!$hostPart") {
          matches = false;
          break;
        }

        r--;
        h--;
      }
    } else {
      matches = false;
    }

    return matches;
  }

  String _getPrevailingRule(List<String> matchingRules) {
    String prevailing;
    int longestLength = 0;

    for (String rule in matchingRules) {
      if (rule.startsWith('!')) {
        prevailing = rule;
        break;
      } else {
        var ruleLength = '.'.allMatches(rule).length + 1;
        if (ruleLength > longestLength) {
          longestLength = ruleLength;
          prevailing = rule;
        }
      }
    }

    return prevailing ?? '*';
  }

  String _trimExceptionRule(String prevailingRule) {
    return prevailingRule.substring(prevailingRule.indexOf('.') + 1);
  }

  String _getPublicSuffix(String host, String prevailingRule) {
    var ruleLength = '.'.allMatches(prevailingRule).length + 1;

    var index = host.length;
    for (int i = 0; i < ruleLength; i++) {
      index = host.lastIndexOf('.', index - 1);
    }

    if (index == -1) {
      return host;
    } else {
      return host.substring(index + 1);
    }
  }

  String _getDomainRoot(String host, String publicSuffix) {
    var domainRoot = host.substring(0, host.lastIndexOf(publicSuffix));

    if (domainRoot == '.' || domainRoot.isEmpty) {
      domainRoot = '';
    } else {
      domainRoot = domainRoot.substring(
          domainRoot.lastIndexOf('.', domainRoot.length - 2) + 1,
          domainRoot.length - 1);
    }

    return domainRoot;
  }

  String _punyEncode(String input) {
    return input.split('.').map((part) {
      var puny = punycodeEncode(part);

      if (puny != "$part-" && puny != part) {
        return "xn--$puny";
      } else {
        return part;
      }
    }).join('.');
  }
}