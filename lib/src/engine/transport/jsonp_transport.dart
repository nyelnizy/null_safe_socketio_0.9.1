import 'dart:async';
import 'dart:html';
import 'dart:js';
import 'package:socket_io_client/src/engine/transport/polling_transport.dart';

/**
 * jsonp_transport.dart
 *
 * Purpose:
 *
 * Description:
 *
 * History:
 *   26/04/2017, Created by jumperchen
 *
 * Copyright (C) 2017 Potix Corporation. All Rights Reserved.
 */

/**
 * Cached regular expressions.
 */

final RegExp rNewline = new RegExp(r'\n');
final RegExp rEscapedNewline = new RegExp(r'\\n');

/**
 * Global JSONP callbacks.
 */

var callbacks;

class JSONPTransport extends PollingTransport {
//  static var empty = (_) => '';
  late int index;
  late Element? script;
  late Element? form;
  late Element? iframe;
  late Element area;
  late String iframeId;

  /**
   * JSONP Polling constructor.
   *
   * @param {Object} opts.
   * @api public
   */
  JSONPTransport(Map opts) : super(opts) {
    this.query ??= {};

    // define global callbacks array if not present
    // we do this here (lazily) to avoid unneeded global pollution
    if (callbacks == null) {
      // we need to consider multiple engines in the same page
      if (context['___eio'] == null) context['___eio'] = [];
      callbacks = context['___eio'];
    }

    // callback identifier
    this.index = callbacks.length;

    // add callback to jsonp global
    callbacks.add((msg) {
      onData(msg);
    });

    // append to query string
    this.query['j'] = this.index;

    // prevent spurious errors from being emitted when the window is unloaded
//    if (window.document != null && window.addEventListener != null) {
//      window.addEventListener('beforeunload', (_) {
////      if (script != null) script.onError.listen(empty);
//      }, false);
//    }
  }

/*
 * JSONP only supports binary as base64 encoded strings
 */
  bool supportsBinary = false;

  /**
   * Closes the socket.
   *
   * @api private
   */
  doClose() {
    if (this.script != null) {
      this.script!.remove();
      this.script = null;
    }

    if (this.form != null) {
      this.form!.remove();
      this.form = null;
      this.iframe = null;
    }
    super.doClose();
  }

  /**
   * Starts a poll cycle.
   *
   * @api private
   */
  doPoll() {
    Element script = document.createElement('script');

    this.script?.remove();
    this.script = null;

    script.attributes["async"] = "true";
    script.attributes["src"] = this.uri();
    script.onError.listen((e) {
      onError('jsonp poll error');
    });

    Node insertAt = document.getElementsByTagName('script')[0];
    if (insertAt != null) {
      insertAt.parentNode!.insertBefore(script, insertAt);
    } else {
      (document.head ?? document.body)!.append(script);
    }
    this.script = script;

    var isUAgecko = window.navigator.userAgent.contains('gecko');

    if (isUAgecko) {
      new Timer(new Duration(milliseconds: 100), () {
        var iframe = document.createElement('iframe');
        document.body!.append(iframe);
        iframe.remove();
      });
    }
  }

  /**
   * Writes with a hidden iframe.
   *
   * @param {String} data to send
   * @param {Function} called upon flush.
   * @api private
   */
  doWrite(data, fn) {
    if (this.form == null) {
      Element form = document.createElement('form');
      Element area = document.createElement('textarea');
      var id = this.iframeId = 'eio_iframe_${this.index}';

      form.className = 'socketio';
      form.style.position = 'absolute';
      form.style.top = '-1000px';
      form.style.left = '-1000px';
      form.attributes["target"] = id;
      form.attributes["method"] = 'POST';
      form.setAttribute('accept-charset', 'utf-8');
      area.attributes["name"] = 'd';
      form.append(area);
      document.body!.append(form);

      this.form = form;
      this.area = area;
    }

    this.form!.attributes["action"] = this.uri();

    var initIframe = () {
      if (iframe != null) {
        try {
          iframe!.remove();
        } catch (e) {
          onError('jsonp polling iframe removal error', e);
        }
      }

      iframe = document.createElement('iframe');
      iframe!.attributes["name"] = iframeId;
      iframe!.attributes["src"] = 'javascript:0';

      iframe!.attributes["id"] = iframeId;

      form!.append(iframe!);
      this.iframe = iframe;
    };

    initIframe();

    // escape \n to prevent it from being converted into \r\n by some UAs
    // double escaping is required for escaped new lines because unescaping of new lines can be done safely on server-side
    data = data.replaceAll(rEscapedNewline, '\\\n');
    this.area.attributes["value"] = data.replaceAll(rNewline, '\\n');

    try {
      this.form?.click();
    } catch (e) {}

    this.iframe!.onLoad.listen((_) {
      initIframe();
      fn();
    });
  }
}
