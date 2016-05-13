/*@@easydoc-start, id=rtmp2js@@
<h2>MEDIA2JS</h2>
<a href="https://doc.rcslabs.ru/index.php/%D0%9A%D0%BE%D0%BC%D0%BF%D0%BE%D0%BD%D0%B5%D0%BD%D1%82%D1%8B_SWF2JS">See doc here</a>
@@easydoc-end@@
*/

package
{
	import flash.display.Sprite;
	import flash.external.ExternalInterface;
	import flash.net.registerClassAlias;
	import flash.system.Capabilities;
	import flash.system.Security;
	
	import mx.logging.Log;
	import mx.logging.LogEventLevel;
	import mx.logging.LogLogger;
	import mx.logging.targets.TraceTarget;
	
	import ru.rcslabs.net.IConnector;
	import ru.rcslabs.net.IConnectorListener;
	import ru.rcslabs.net.connection.RTMPConnector;
	import ru.rcslabs.storage.IDataStorage;
	import ru.rcslabs.storage.SharedDataStorage;
	import ru.rcslabs.storage.UserDataStorage;
	import ru.rcslabs.utils.Logger;
	import ru.rcslabs.webcall.api.ICallClient;
	import ru.rcslabs.webcall.api.events.CallEvent;
	import ru.rcslabs.webcall.api.events.SessionEvent;
	import ru.rcslabs.webcall.business.calls.CallService;
	import ru.rcslabs.webcall.vo.CaptchaParamsVO;
	import ru.rcslabs.webcall.vo.ClientInfoVO;
	
	[SWF(width="216", height="180", frameRate="30")]
	public class RTMP2JS extends Sprite  implements IConnectorListener, ICallClient
	{	
		private var callService:CallService;
		
		private var conn:RTMPConnector;
		
		private var sharedStorage:IDataStorage;
		
		private var userStorage:IDataStorage;
		
		private var credentials:Object;
		
		private var info:ClientInfoVO;
		
		private var data:Object;
		
		private static var JSHANDLER:String = null;
		
		public function RTMP2JS()
		{
			super();
			Security.allowDomain("*");
			Security.allowInsecureDomain("*");
			if(ExternalInterface.available) 
				runInBrowser();
			else
				runAsDebug();
		}	
		
		private function runInBrowser():void
		{
			var p:Object = loaderInfo.parameters;		
			Logger.init(undefined != p['logLevel'] ? p['logLevel'] : "NONE");
			
			if(undefined == p['cbSignaling']){
				Log.getLogger(Logger.DEFAULT_CATEGORY).error("Callback 'cbSignaling' undefined");	
				throw new Error("You have to define 'cbSignaling' on flashVars");	
			}else{
				JSHANDLER = p['cbSignaling'];
			}

			if(undefined == p['cbReady']){
				Log.getLogger(Logger.DEFAULT_CATEGORY).error("Callback 'cbReady' undefined");	
				throw new Error("You have to define 'cbReady' on flashVars");	
			}

			info = ClientInfoVO.createInfo();
			conn = new RTMPConnector();
			conn.reuseSuccessOnly = true;
			conn.addConnectionListener(this);
			callService = new CallService();
			callService.serviceName = "callService";
			callService.connector = conn;
			
			sharedStorage = new SharedDataStorage();
			
			conn.addMessageHandler('onCallEvent', onCallEvent);
			conn.addMessageHandler('onConnectionEvent', onSessionEvent);
			conn.addMessageHandler('onVerificationFailed', onVerificationFailed);
			
			ExternalInterface.addCallback("getVersion", getVersion);
			ExternalInterface.addCallback("addEndpoint", addEndpoint);	
			ExternalInterface.addCallback("connect", connect);	
			ExternalInterface.addCallback("close", close);		
			ExternalInterface.addCallback("notifyMessage", notifyMessage);				
			ExternalInterface.addCallback("storage", storage);
			ExternalInterface.addCallback("setClientInfo", setClientInfo);
			ExternalInterface.call(loaderInfo.parameters.cbReady);
			
			if(Log.isDebug()){
				Log.getLogger(Logger.DEFAULT_CATEGORY).debug(loaderInfo.url);
				Log.getLogger(Logger.DEFAULT_CATEGORY).debug(info.pageUrl);				
				Log.getLogger(Logger.DEFAULT_CATEGORY).debug(info.userAgent);
			}			
		}
		
		private function runAsDebug():void
		{			
			conn = new RTMPConnector();
			conn.addEndpoint("rtmp://192.168.1.230/webcall2/communicator");
			conn.reuseSuccessOnly = true;
			conn.addConnectionListener(this);
			
			callService = new CallService();
			callService.serviceName = "callService";
			callService.connector = conn;
			
			sharedStorage = new SharedDataStorage();
			
			conn.addMessageHandler('onCallEvent', onCallEvent);
			conn.addMessageHandler('onConnectionEvent', onSessionEvent);
			conn.addMessageHandler('onVerificationFailed', onVerificationFailed);
			
			info = new ClientInfoVO();
			//webcallRequest("open", {phone : "1010", password : "1234"});		
		}
		
		// JS->AS
		
		private function setClientInfo(prop:String, value:String):void
		{
			if('pageUrl' == prop){
				info.pageUrl = value;
				Log.getLogger(Logger.DEFAULT_CATEGORY).debug(info.pageUrl);
			}else{
				throw new Error("Invalid param {"+prop+"}");
			}			
		}
		
		private function getVersion():String
		{
			var s:String = WEBCALL::APP_VERSION;
			if(CallService.SERVICE_VERSION){
				s = s.concat(", ", CallService.SERVICE_VERSION[0], ".", CallService.SERVICE_VERSION[1]);
			}
			return s;
		}
		
		private function addEndpoint(url:String):void{
			conn.addEndpoint(url);
		}
		
		private function connect():void{
			conn.connect();
		}

		private function close():void{
			callService.close(); 
		}

		private function notifyMessage(message:Object):void
		{
			switch(message.type)
			{
				case("START_SESSION"): 
					credentials = {
						username : message.username, 
						password : message.password,
						captcha : null
					}; 
					
					if(undefined != message.challenge && undefined != message.code){
						var p:CaptchaParamsVO = new CaptchaParamsVO();
						p.challenge = message.challenge;
						p.response = message.code;
						credentials.captcha = p;
					}	
					
					data = {};
					
					for(var k:String in message){
						if(-1 == ["phone", "password", "challenge", "code"].indexOf(k)){
							Log.getLogger(Logger.DEFAULT_CATEGORY).info("Additional parameter " + k + "=" + message[k]);
							data[k] = message[k];
						}
					}
					
					if(!credentials.captcha){
						callService.open(credentials.username, credentials.password, info, data);
					} else {
						callService.open(credentials.username, credentials.password, info, data, credentials.captcha);
					}
					break;
				
				case("START_CALL"): 
					var av_params:String = (message.vv[1] ? "video" : "audio");		
					callService.startCall(message.bUri, av_params); 
					break;

				case("ACCEPT_CALL"): 	
					var av_params:String = (message.vv[1] ? "video" : "audio");
					callService.acceptCall(message.callId, av_params); 
					break;
				
				case("REJECT_CALL"): 	
					callService.declineCall(message.callId); 
					break;
				
				case("HANGUP_CALL"): 	
					if(callService.getCallById(message.callId)) 
						callService.hangupCall(message.callId); 
					break;
				
				case("SEND_DTMF_SIGNAL"): 		
					callService.sendDTMF(message.callId, message.dtmf); 
					break;
				
				default: 
					Log.getLogger(Logger.DEFAULT_CATEGORY).warn("Unknown message type "+message.type);
			}
		}
		
		private function storage(target:String, callName:String, key:String=null, value:*=null):*
		{
			var s:IDataStorage;
			if('user' == target){
				s = userStorage;
			}else if('shared' == target){
				s = sharedStorage;
			}	
			
			if(null == s){return;}
			var i:int = ['hasKey', 'getValue', 'setValue', 'deleteValue', 'clear'].indexOf(callName);
			if(-1 == i){return;}	
			
			switch(i){
				case(0): return s.hasKey(key);
				case(1): return s.getValue(key);
				case(2): return s.setValue(key, value);
				case(3): return s.deleteValue(key);
				case(4): return s.clear();
			}
		}
		
		/** IConnectorListener */

		public function onConnectionConnect(connector:IConnector):void
		{
			if(ExternalInterface.available)
				ExternalInterface.call(JSHANDLER, new SessionEvent("CONNECTING"));
		}
		
		public function onConnectionConnected(connector:IConnector):void
		{
			callService.getServiceVersion();
			if(ExternalInterface.available)
				ExternalInterface.call(JSHANDLER, new SessionEvent("CONNECTED"));
		}
		
		public function onConnectionFailed(connector:IConnector):void
		{
			if(ExternalInterface.available)			
				ExternalInterface.call(JSHANDLER, new SessionEvent("CONNECTION_FAILED"));
		}
		
		public function onConnectionClosed(connector:IConnector):void
		{
			if(ExternalInterface.available)			
				ExternalInterface.call(JSHANDLER, new SessionEvent("CONNECTION_FAILED"));
		}		
		
		/** ICallClient */
		
		public function onCallEvent(event:CallEvent):void
		{
			var event2:Object = {
				sessionId : event.connectionUid,
				type : event.type,
				callId : event.callId,
				playUrlVideo: event.playUrlVideo,
				playUrlVoice: event.playUrlVoice,
				publishUrlVideo: event.publishUrlVideo,
				publishUrlVoice: event.publishUrlVoice
			} 

			if(event['message'] != undefined && null != event.message) event2.reason  = event.message;
			if(event['stage'] != undefined   && null != event.stage)   event2.stage   = event.stage;
			if(event['timeBeforeFinish'] != undefined && event.timeBeforeFinish) event2.timeBeforeFinish = event.timeBeforeFinish;

			if(ExternalInterface.available)			
				ExternalInterface.call(JSHANDLER, event2);
		}

		public function onSessionEvent(event:SessionEvent):void
		{
			var compatibleType:String = "UNKNOWN";

			switch (event.type)
			{
				case SessionEvent.CONNECTING:
					compatibleType = "SESSION_STARTING";
					break;

				case SessionEvent.CONNECTED:
					userStorage = new UserDataStorage(credentials.username);
					callService.connector.connectionUid = event.connectionUid;
					compatibleType = "SESSION_STARTED";
					break;

				case SessionEvent.CONNECTION_BROKEN:
				case SessionEvent.CONNECTION_FAILED:
				case SessionEvent.CONNECTION_ERROR:
					compatibleType = "SESSION_FAILED";
					break;
			}
			
			var event2:Object = {
				sessionId : event.connectionUid,
				type : compatibleType,
				message : event.message
			} 

			if(ExternalInterface.available)			
				ExternalInterface.call(JSHANDLER, event2);			
		}
		
		public function onVerificationFailed(uid:String, reason:String, message:String):void
		{
			var event:Object = {
				type : "VERIFICATION_FAILED",
				sessionId : uid,
				reason : reason,
				message : message,
				message : event.message
			} 

			if(ExternalInterface.available)			
				ExternalInterface.call(JSHANDLER, event);
		}
		
	}
}