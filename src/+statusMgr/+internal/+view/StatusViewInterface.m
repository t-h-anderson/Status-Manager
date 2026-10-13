classdef (Abstract) StatusViewInterface < handle & matlab.mixin.Heterogeneous
    %STATUSVIEWINTERFACE Public contract for views that observe a Stack.
    %
    % This is intentionally narrow — it declares only what callers and
    % mocks need. Implementation, dispatching, and shared property
    % storage live in statusMgr.internal.view.StatusViewBase. Concrete
    % views (Popup, CommandWindow, FileLog) extend the base, and tests
    % that need a stand-in can mock this interface directly.

    properties (Abstract, SetAccess = protected)
        % The Stack this view is observing.
        Stack statusMgr.internal.StackInterface
    end

    methods (Abstract)
        % True if the view is currently capable of presenting status
        % updates (e.g. a Popup whose parent figure is still alive).
        tf = isVisible(obj)

        % Bind the view to a Stack and start listening for updates.
        % Implementations are expected to wire a StatusUpdated listener
        % so that subsequent stack changes refresh the view. An empty
        % stack disconnects listeners and releases active display resources
        % without deleting the view; it can be rebound later.
        setStack(obj, stack)
    end

    methods (Static, Sealed, Access = protected)
        function obj = getDefaultScalarElement() %#ok<STOUT>
            % Required by matlab.mixin.Heterogeneous. We never need
            % auto-generated default elements, so error if called.
            error("statusMgr:view:noDefault", ...
                "StatusViewInterface has no default scalar element.");
        end
    end

end
