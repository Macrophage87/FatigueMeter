using Toybox.Lang;
using Toybox.Application;
using Toybox.WatchUi;

//! FatigueMeter application entry point (data field). Owns the view lifecycle,
//! forwards settings changes, and finalizes the Session Result / ledger fold when
//! the activity ends (App.onStop is the reliable "app going away" hook for a data
//! field). See white paper §8 for the storage/finalize model.
//! Integration coverage (#81): the lifecycle hooks (onStart/onStop/getInitialView)
//! are verified per-release — see docs/release-checklist.md (unconstructable in the
//! headless harness; onStop is trivial guarded delegation to the view).
class FatigueMeterApp extends Application.AppBase {

    hidden var view;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
    }

    //! Ride ended / app removed: finalize the ledger + Session Result, then
    //! release the raw ANT+ HRM channel (#47). Both guarded (separate blocks so a
    //! finalize throw can't skip the release, and vice versa). NOTE: a Data Field
    //! may NOT call Sensor.(un)registerSensorDataListener -- it throws "Permission
    //! Required" at runtime (see #42); RR comes from a raw ANT+ channel, released
    //! here via ant.stop() -> GenericChannel.release(), which IS Ant-namespace and
    //! Data-Field-legal.
    function onStop(state) {
        try {
            if (view != null) { view.finalizeSession(); }
        } catch (e) { }
        try {
            if (view != null) { view.releaseAnt(); }
        } catch (e) { }
    }

    function getInitialView() {
        view = new FatigueMeterView();
        return [ view ];
    }

    //! Settings changed in Garmin Connect / Express -> refresh the live Config.
    //! Guarded (§8.4, #13): a settings-change exception must not crash the whole
    //! field to the CIQ banner. The view's onSettingsChanged is itself a no-op
    //! when construction failed (its `ready` gate).
    function onSettingsChanged() {
        try {
            if (view != null) { view.onSettingsChanged(); }
        } catch (e) { }
        WatchUi.requestUpdate();
    }
}
