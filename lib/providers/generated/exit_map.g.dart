// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../exit_map.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ExitMapOrigin)
final exitMapOriginProvider = ExitMapOriginProvider._();

final class ExitMapOriginProvider
    extends
        $NotifierProvider<
          ExitMapOrigin,
          RoutedProbeState<String, ExitMapPlace>
        > {
  ExitMapOriginProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'exitMapOriginProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$exitMapOriginHash();

  @$internal
  @override
  ExitMapOrigin create() => ExitMapOrigin();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RoutedProbeState<String, ExitMapPlace> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<RoutedProbeState<String, ExitMapPlace>>(value),
    );
  }
}

String _$exitMapOriginHash() => r'98348f941b531d34180a4ae0f65d84be0bcf4447';

abstract class _$ExitMapOrigin
    extends $Notifier<RoutedProbeState<String, ExitMapPlace>> {
  RoutedProbeState<String, ExitMapPlace> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              RoutedProbeState<String, ExitMapPlace>,
              RoutedProbeState<String, ExitMapPlace>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                RoutedProbeState<String, ExitMapPlace>,
                RoutedProbeState<String, ExitMapPlace>
              >,
              RoutedProbeState<String, ExitMapPlace>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
