// GENERATED — KHÔNG SỬA TAY. Nguồn: configs/abi/host_packages.yaml
// Sinh lại: bash tools/cmd/dyniface.sh packages --write
//
// Import (không dùng) mọi library public của package host → kernel host +
// anchor chứa trọn package; module dùng chung, không tự mang bản riêng
// (tránh "already loaded"). docs/dynmod_build_once_plan.md P4.1.
// ignore_for_file: unused_import, depend_on_referenced_packages, deprecated_member_use

import 'package:archive/archive.dart' as h0;
import 'package:archive/archive_io.dart' as h1;
import 'package:async/async.dart' as h2;
import 'package:audioplayers/audioplayers.dart' as h3;
import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart' as h4;
import 'package:cached_network_image/cached_network_image.dart' as h5;
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart' as h6;
import 'package:characters/characters.dart' as h7;
import 'package:clarity_flutter/clarity_flutter.dart' as h8;
import 'package:clock/clock.dart' as h9;
import 'package:collection/algorithms.dart' as h10;
import 'package:collection/collection.dart' as h11;
import 'package:collection/equality.dart' as h12;
import 'package:collection/iterable_zip.dart' as h13;
import 'package:collection/priority_queue.dart' as h14;
import 'package:collection/wrappers.dart' as h15;
import 'package:connectivity_plus/connectivity_plus.dart' as h16;
import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart' as h17;
import 'package:connectivity_plus_platform_interface/method_channel_connectivity.dart' as h18;
import 'package:content_kit/content_kit.dart' as h19;
import 'package:crypto/crypto.dart' as h20;
import 'package:csslib/parser.dart' as h21;
import 'package:csslib/visitor.dart' as h22;
import 'package:dartz/dartz.dart' as h23;
import 'package:dartz/dartz_streaming.dart' as h24;
import 'package:dartz/dartz_unsafe.dart' as h25;
import 'package:device_info_plus/device_info_plus.dart' as h26;
import 'package:device_info_plus_platform_interface/device_info_plus_platform_interface.dart' as h27;
import 'package:dio/dio.dart' as h28;
import 'package:dio/io.dart' as h29;
import 'package:dyn_loader/dyn_loader.dart' as h30;
import 'package:dynamic_modules/dynamic_modules.dart' as h31;
import 'package:file/chroot.dart' as h32;
import 'package:file/file.dart' as h33;
import 'package:file/local.dart' as h34;
import 'package:file/memory.dart' as h35;
import 'package:fixnum/fixnum.dart' as h36;
import 'package:flutter/animation.dart' as h37;
import 'package:flutter/cupertino.dart' as h38;
import 'package:flutter/foundation.dart' as h39;
import 'package:flutter/gestures.dart' as h40;
import 'package:flutter/material.dart' as h41;
import 'package:flutter/painting.dart' as h42;
import 'package:flutter/physics.dart' as h43;
import 'package:flutter/rendering.dart' as h44;
import 'package:flutter/scheduler.dart' as h45;
import 'package:flutter/semantics.dart' as h46;
import 'package:flutter/services.dart' as h47;
import 'package:flutter/widget_previews.dart' as h48;
import 'package:flutter/widgets.dart' as h49;
import 'package:flutter_cache_manager/file.dart' as h50;
import 'package:flutter_cache_manager/flutter_cache_manager.dart' as h51;
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as h52;
import 'package:flutter_inappwebview_android/flutter_inappwebview_android.dart' as h53;
import 'package:flutter_inappwebview_internal_annotations/flutter_inappwebview_internal_annotations.dart' as h54;
import 'package:flutter_inappwebview_ios/flutter_inappwebview_ios.dart' as h55;
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart' as h56;
import 'package:flutter_localizations/flutter_localizations.dart' as h57;
import 'package:flutter_riverpod/flutter_riverpod.dart' as h58;
import 'package:flutter_svg/flutter_svg.dart' as h59;
import 'package:flutter_svg/svg.dart' as h60;
import 'package:freezed_annotation/freezed_annotation.dart' as h61;
import 'package:gap/gap.dart' as h62;
import 'package:go_router/go_router.dart' as h63;
import 'package:google_fonts/google_fonts.dart' as h64;
import 'package:gradient_borders/gradient_borders.dart' as h65;
import 'package:graphs/graphs.dart' as h66;
import 'package:hive/hive.dart' as h67;
import 'package:hive_flutter/adapters.dart' as h68;
import 'package:hive_flutter/hive_flutter.dart' as h69;
import 'package:html/dom.dart' as h70;
import 'package:html/dom_parsing.dart' as h71;
import 'package:html/html_escape.dart' as h72;
import 'package:html/parser.dart' as h73;
import 'package:http/http.dart' as h74;
import 'package:http/io_client.dart' as h75;
import 'package:http/retry.dart' as h76;
import 'package:http/testing.dart' as h77;
import 'package:http_parser/http_parser.dart' as h78;
import 'package:image/image.dart' as h79;
import 'package:intl/date_symbol_data_custom.dart' as h80;
import 'package:intl/date_symbol_data_file.dart' as h81;
import 'package:intl/date_symbol_data_local.dart' as h82;
import 'package:intl/date_symbols.dart' as h83;
import 'package:intl/date_time_patterns.dart' as h84;
import 'package:intl/find_locale.dart' as h85;
import 'package:intl/intl.dart' as h86;
import 'package:intl/intl_default.dart' as h87;
import 'package:intl/intl_standalone.dart' as h88;
import 'package:intl/locale.dart' as h89;
import 'package:intl/message_format.dart' as h90;
import 'package:intl/message_lookup_by_library.dart' as h91;
import 'package:intl/number_symbols.dart' as h92;
import 'package:intl/number_symbols_data.dart' as h93;
import 'package:isolate_manager/isolate_manager.dart' as h94;
import 'package:json_annotation/json_annotation.dart' as h95;
import 'package:loading_kit/loading_kit.dart' as h96;
import 'package:logger/logger.dart' as h97;
import 'package:logger/web.dart' as h98;
import 'package:logging/logging.dart' as h99;
import 'package:lottie/lottie.dart' as h100;
import 'package:main_app_package/main.dart' as h101;
import 'package:main_app_package/main_app_package.dart' as h102;
import 'package:material_color_utilities/material_color_utilities.dart' as h103;
import 'package:meta/dart2js.dart' as h104;
import 'package:meta/meta.dart' as h105;
import 'package:meta/meta_meta.dart' as h106;
import 'package:mime/mime.dart' as h107;
import 'package:octo_image/octo_image.dart' as h108;
import 'package:package_info_plus/package_info_plus.dart' as h109;
import 'package:package_info_plus_platform_interface/method_channel_package_info.dart' as h110;
import 'package:package_info_plus_platform_interface/package_info_data.dart' as h111;
import 'package:package_info_plus_platform_interface/package_info_platform_interface.dart' as h112;
import 'package:path/path.dart' as h113;
import 'package:path_parsing/path_parsing.dart' as h114;
import 'package:path_provider/path_provider.dart' as h115;
import 'package:path_provider_android/messages.g.dart' as h116;
import 'package:path_provider_android/path_provider_android.dart' as h117;
import 'package:path_provider_foundation/path_provider_foundation.dart' as h118;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart' as h119;
import 'package:petitparser/core.dart' as h120;
import 'package:petitparser/debug.dart' as h121;
import 'package:petitparser/definition.dart' as h122;
import 'package:petitparser/expression.dart' as h123;
import 'package:petitparser/indent.dart' as h124;
import 'package:petitparser/matcher.dart' as h125;
import 'package:petitparser/parser.dart' as h126;
import 'package:petitparser/petitparser.dart' as h127;
import 'package:petitparser/reflection.dart' as h128;
import 'package:pinput/pinput.dart' as h129;
import 'package:platform/platform.dart' as h130;
import 'package:platform/testing.dart' as h131;
import 'package:plugin_platform_interface/plugin_platform_interface.dart' as h132;
import 'package:pointer_interceptor/pointer_interceptor.dart' as h133;
import 'package:pointer_interceptor_ios/pointer_interceptor_ios.dart' as h134;
import 'package:pointer_interceptor_platform_interface/pointer_interceptor_platform_interface.dart' as h135;
import 'package:pretty_dio_logger/pretty_dio_logger.dart' as h136;
import 'package:protobuf/meta.dart' as h137;
import 'package:protobuf/protobuf.dart' as h138;
import 'package:pub_semver/pub_semver.dart' as h139;
import 'package:qr/qr.dart' as h140;
import 'package:qr_flutter/qr_flutter.dart' as h141;
import 'package:restart_app/restart_app.dart' as h142;
import 'package:rive/rive.dart' as h143;
import 'package:rive_native/focus.dart' as h144;
import 'package:rive_native/layout_engine.dart' as h145;
import 'package:rive_native/math.dart' as h146;
import 'package:rive_native/platform.dart' as h147;
import 'package:rive_native/rive_audio.dart' as h148;
import 'package:rive_native/rive_luau.dart' as h149;
import 'package:rive_native/rive_native.dart' as h150;
import 'package:rive_native/rive_pathops.dart' as h151;
import 'package:rive_native/rive_text.dart' as h152;
import 'package:rive_native/scripting_workspace.dart' as h153;
import 'package:rive_native/semantics.dart' as h154;
import 'package:rive_native/utilities.dart' as h155;
import 'package:riverpod/riverpod.dart' as h156;
import 'package:rxdart/rxdart.dart' as h157;
import 'package:rxdart/streams.dart' as h158;
import 'package:rxdart/subjects.dart' as h159;
import 'package:rxdart/transformers.dart' as h160;
import 'package:rxdart/utils.dart' as h161;
import 'package:sentry/sentry.dart' as h162;
import 'package:sentry/sentry_io.dart' as h163;
import 'package:sentry_flutter/sentry_flutter.dart' as h164;
import 'package:shared_preferences/shared_preferences.dart' as h165;
import 'package:shared_preferences_android/shared_preferences_android.dart' as h166;
import 'package:shared_preferences_foundation/shared_preferences_foundation.dart' as h167;
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart' as h168;
import 'package:shared_preferences_platform_interface/method_channel_shared_preferences.dart' as h169;
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart' as h170;
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart' as h171;
import 'package:shared_preferences_platform_interface/types.dart' as h172;
import 'package:shimmer_animation/shimmer_animation.dart' as h173;
import 'package:source_span/source_span.dart' as h174;
import 'package:sqflite/sqflite.dart' as h175;
import 'package:sqflite/sqflite_dev.dart' as h176;
import 'package:sqflite/sql.dart' as h177;
import 'package:sqflite/sqlite_api.dart' as h178;
import 'package:sqflite_android/sqflite_android.dart' as h179;
import 'package:sqflite_common/sqflite.dart' as h180;
import 'package:sqflite_common/sqflite_dev.dart' as h181;
import 'package:sqflite_common/sqflite_logger.dart' as h182;
import 'package:sqflite_common/sql.dart' as h183;
import 'package:sqflite_common/sqlite_api.dart' as h184;
import 'package:sqflite_darwin/sqflite_darwin.dart' as h185;
import 'package:sqflite_platform_interface/sqflite_platform_interface.dart' as h186;
import 'package:stack_trace/stack_trace.dart' as h187;
import 'package:state_notifier/state_notifier.dart' as h188;
import 'package:stream_channel/isolate_channel.dart' as h189;
import 'package:stream_channel/stream_channel.dart' as h190;
import 'package:string_scanner/string_scanner.dart' as h191;
import 'package:styled_text/styled_text.dart' as h192;
import 'package:synchronized/extension.dart' as h193;
import 'package:synchronized/synchronized.dart' as h194;
import 'package:term_glyph/term_glyph.dart' as h195;
import 'package:typed_data/typed_buffers.dart' as h196;
import 'package:typed_data/typed_data.dart' as h197;
import 'package:url_launcher/link.dart' as h198;
import 'package:url_launcher/url_launcher.dart' as h199;
import 'package:url_launcher/url_launcher_string.dart' as h200;
import 'package:url_launcher_android/url_launcher_android.dart' as h201;
import 'package:url_launcher_ios/url_launcher_ios.dart' as h202;
import 'package:url_launcher_platform_interface/link.dart' as h203;
import 'package:url_launcher_platform_interface/method_channel_url_launcher.dart' as h204;
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart' as h205;
import 'package:uuid/constants.dart' as h206;
import 'package:uuid/data.dart' as h207;
import 'package:uuid/enums.dart' as h208;
import 'package:uuid/parsing.dart' as h209;
import 'package:uuid/rng.dart' as h210;
import 'package:uuid/uuid.dart' as h211;
import 'package:uuid/uuid_value.dart' as h212;
import 'package:uuid/v1.dart' as h213;
import 'package:uuid/v4.dart' as h214;
import 'package:uuid/v5.dart' as h215;
import 'package:uuid/v6.dart' as h216;
import 'package:uuid/v7.dart' as h217;
import 'package:uuid/v8.dart' as h218;
import 'package:uuid/v8generic.dart' as h219;
import 'package:uuid/validation.dart' as h220;
import 'package:vector_graphics/vector_graphics.dart' as h221;
import 'package:vector_graphics/vector_graphics_compat.dart' as h222;
import 'package:vector_graphics_codec/vector_graphics_codec.dart' as h223;
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart' as h224;
import 'package:vector_math/hash.dart' as h225;
import 'package:vector_math/vector_math.dart' as h226;
import 'package:vector_math/vector_math_64.dart' as h227;
import 'package:vector_math/vector_math_geometry.dart' as h228;
import 'package:vector_math/vector_math_lists.dart' as h229;
import 'package:vector_math/vector_math_operations.dart' as h230;
import 'package:video_player/video_player.dart' as h231;
import 'package:video_player_android/video_player_android.dart' as h232;
import 'package:video_player_avfoundation/video_player_avfoundation.dart' as h233;
import 'package:video_player_platform_interface/video_player_platform_interface.dart' as h234;
import 'package:wakelock_plus/wakelock_plus.dart' as h235;
import 'package:wakelock_plus_platform_interface/messages.g.dart' as h236;
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart' as h237;
import 'package:web_socket/io_web_socket.dart' as h238;
import 'package:web_socket/testing.dart' as h239;
import 'package:web_socket/web_socket.dart' as h240;
import 'package:web_socket_channel/adapter_web_socket_channel.dart' as h241;
import 'package:web_socket_channel/io.dart' as h242;
import 'package:web_socket_channel/status.dart' as h243;
import 'package:web_socket_channel/web_socket_channel.dart' as h244;
import 'package:webview_flutter/webview_flutter.dart' as h245;
import 'package:webview_flutter_android/webview_flutter_android.dart' as h246;
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart' as h247;
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart' as h248;
import 'package:xml/xml.dart' as h249;
import 'package:xml/xml_events.dart' as h250;
import 'package:xml/xpath.dart' as h251;
import 'package:xmlstream/xmlstream.dart' as h252;
import 'package:xxh3/xxh3.dart' as h253;

/// Package nằm ở host (sdk + t0_required + t1_frozen_pure_dart) —
/// `HostServices.capabilities` (docs/dynmod_build_once_plan.md P3).
const Set<String> kHostPackages = <String>{
  'archive',
  'async',
  'audioplayers',
  'audioplayers_android',
  'audioplayers_darwin',
  'audioplayers_platform_interface',
  'cached_network_image',
  'cached_network_image_platform_interface',
  'characters',
  'clarity_flutter',
  'clock',
  'collection',
  'connectivity_plus',
  'connectivity_plus_platform_interface',
  'content_kit',
  'crypto',
  'csslib',
  'cupertino_icons',
  'dartz',
  'dbus',
  'device_info_plus',
  'device_info_plus_platform_interface',
  'dio',
  'dyn_loader',
  'dynamic_modules',
  'ffi',
  'file',
  'fixnum',
  'flutter',
  'flutter_cache_manager',
  'flutter_inappwebview',
  'flutter_inappwebview_android',
  'flutter_inappwebview_internal_annotations',
  'flutter_inappwebview_ios',
  'flutter_inappwebview_platform_interface',
  'flutter_localizations',
  'flutter_riverpod',
  'flutter_svg',
  'freezed_annotation',
  'gap',
  'go_router',
  'google_fonts',
  'gradient_borders',
  'graphs',
  'hive',
  'hive_flutter',
  'html',
  'http',
  'http_parser',
  'image',
  'intl',
  'isolate_manager',
  'jni',
  'json_annotation',
  'loading_kit',
  'logger',
  'logging',
  'lottie',
  'main_app_package',
  'material_color_utilities',
  'meta',
  'mime',
  'nm',
  'objective_c',
  'octo_image',
  'package_info_plus',
  'package_info_plus_platform_interface',
  'path',
  'path_parsing',
  'path_provider',
  'path_provider_android',
  'path_provider_foundation',
  'path_provider_platform_interface',
  'petitparser',
  'pinput',
  'platform',
  'plugin_platform_interface',
  'pointer_interceptor',
  'pointer_interceptor_ios',
  'pointer_interceptor_platform_interface',
  'posix',
  'pretty_dio_logger',
  'protobuf',
  'pub_semver',
  'qr',
  'qr_flutter',
  'restart_app',
  'rive',
  'rive_native',
  'riverpod',
  'rxdart',
  'sentry',
  'sentry_flutter',
  'shared_preferences',
  'shared_preferences_android',
  'shared_preferences_foundation',
  'shared_preferences_platform_interface',
  'shimmer_animation',
  'sky_engine',
  'source_span',
  'sqflite',
  'sqflite_android',
  'sqflite_common',
  'sqflite_darwin',
  'sqflite_platform_interface',
  'stack_trace',
  'state_notifier',
  'stream_channel',
  'string_scanner',
  'styled_text',
  'synchronized',
  'term_glyph',
  'typed_data',
  'url_launcher',
  'url_launcher_android',
  'url_launcher_ios',
  'url_launcher_platform_interface',
  'uuid',
  'vector_graphics',
  'vector_graphics_codec',
  'vector_graphics_compiler',
  'vector_math',
  'video_player',
  'video_player_android',
  'video_player_avfoundation',
  'video_player_platform_interface',
  'wakelock_plus',
  'wakelock_plus_platform_interface',
  'web_socket',
  'web_socket_channel',
  'webview_flutter',
  'webview_flutter_android',
  'webview_flutter_platform_interface',
  'webview_flutter_wkwebview',
  'win32',
  'win32_registry',
  'xml',
  'xmlstream',
  'xxh3',
};
