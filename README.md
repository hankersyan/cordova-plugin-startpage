# cordova-plugin-startpage
A plugin to modify the Cordova start page in run time.

This plugin let's you change the start page to different URLs, not restricted by the widget.content.src entry in config.xml
which normally is static until you provide an application update.

## Issue: Not load the startPage on android back button and reopen app
```java
public class MainActivity extends CordovaActivity
{
    @Override
    public void onCreate(Bundle savedInstanceState)
    {
        super.onCreate(savedInstanceState);

        // enable Cordova apps to be started in the background
        Bundle extras = getIntent().getExtras();
        if (extras != null && extras.getBoolean("cdvStartInBackground", false)) {
            moveTaskToBack(true);
        }

        getSavedStartPage();

        // Set by <content src="index.html" /> in config.xml
        loadUrl(launchUrl);
    }

    private void getSavedStartPage() {
        SharedPreferences defaults = PreferenceManager.getDefaultSharedPreferences(this.getApplicationContext());
        String startPage = defaults.getString("StartPage", null);
        if (startPage != null && !startPage.isEmpty()) {
            launchUrl = startPage;
        }
    }
}
```

## Usage
First, reference the plugin with:
```js
var startpage = cordova.require('cordova-plugin-startpage.StartPagePlugin');
```

### To set the start page for future app boot, run
```js
startpage.setStartPageUrl('http://myUrl.com', function success(){}, function error(){});
```

### To get the start page
```js
startpage.getStartPageUrl(function(startPageUrl){alert(startPageUrl);});
```

### To reload the url from widget.content.src in config.xml
```js
startpage.loadContentSrc();
```

### Load the current start page (the last one you set, will fallback to widget.content.src if nothing was set)
```js
startpage.loadStartPage();
```

### Reset the start page to the one defined in widget.content.src (the usual cordova behaviour)
```js
startpage.resetStartPageToContentSrc(function success(){}, function error(){});
```

### Append application version and build version as query params
If you define `<preference name="IncludeVersionInStartPageUrl" value="true" />` in your config.xml, the plugin will communicate to cordova to load the page requests with additional URL query params: `nativeVersion` and `buildVersion` of your application. 

## Important:
- Only iOS and Android are supported for now.
- Verified all functionality on Cordova 6.2.0.
