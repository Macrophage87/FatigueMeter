using Toybox.Lang;
using Toybox.Application;
using Toybox.WatchUi;

//! FatigueMeter application entry point (data field). Owns the view lifecycle,
//! forwards settings changes, and finalizes the Session Result / ledger fold when
//! the activity ends (App.onStop is the reliable "app going away" hook for a data
//! field). See white paper §8 for the storage/finalize model.
class FatigueMeterApp extends Application.AppBase {

    hidden var view;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
    }

    //! Ride ended / app removed: finalize the ledger + Session Result once.
    //! Guarded so nothing here can crash on shutdown. NOTE: a Data Field may NOT
    //! call Sensor.(un)registerSensorDataListener -- it throws "Permission
    //! Required" at runtime (surfaced once the tests actually ran, see #42). This
    //! app never registers a Sensor listener (RR comes from a raw ANT+ channel),
    //! so there is nothing to unregister here.
    function onStop(state) {
        try {
            if (view != null) { view.finalizeSession(); }
        } catch (e) { }
    }

    function getInitialView() {
        view = new FatigueMeterView();
        return [ view ];
    }

    //! Settings changed in Garmin Connect / Express -> refresh the live Config.
    function onSettingsChanged() {
        if (view != null) { view.onSettingsChanged(); }
        WatchUi.requestUpdate();
    }
}
