#!/usr/bin/env ruby

# (c) 2012 Jesse Newland, jesse@jnewland.com
# (c) 2011 Rdio Inc
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

require 'sinatra'
require 'uri'
$LOAD_PATH << './lib'
require 'rdio'

RDIO_CONSUMER_KEY    = ENV['RDIO_CONSUMER_KEY']
RDIO_CONSUMER_SECRET = ENV['RDIO_CONSUMER_SECRET']


enable :sessions
disable :protection

set :public_folder, File.dirname(__FILE__) + '/static'

get '/' do
  access_token = session[:at]
  access_token_secret = session[:ats]
  if access_token and access_token_secret
    response = '<html><body><form method="get" enctype="text/plain" action="/CreateStation">
    Station URL: <input type="text" name="station_url"><br>
    Playlist Name: <input type="text" name="new_playlist_name"> (optional, defaults to the name of the station)<br>
    IF A PLAYLIST WITH THE SAME NAME EXISTS, IT WILL BE DELETED<br>
    <input type="submit"></form>'
    return response
  else
    redirect to('/login')
  end
end

get '/CreateStation' do
  access_token = session[:at]
  access_token_secret = session[:ats]
  if access_token and access_token_secret and params[:station_url]
    rdio = Rdio.new([RDIO_CONSUMER_KEY, RDIO_CONSUMER_SECRET],
    [access_token, access_token_secret])
    response = "<html><body>"
    user_key  = rdio.call('currentUser')['result']['key']
    station = rdio.call('getObjectFromUrl', { :url => params[:station_url] })['result']
    station_key = station["key"]
    station_name = station["name"]
    response += "Station name: %s<br>" % station_name
    station_tracks = rdio.call('generateStation', { :station_key => station_key, :count => "100" })['result']["tracks"]
    station_tracks_keys_array = []
    response += "Tracks:<br>"
    station_tracks.each do |track|
      response += "%s - %s <br>" % [track["artist"], track["name"]]
      station_tracks_keys_array << track["key"]
    end
    station_tracks_keys = station_tracks_keys_array * ","
    response += "Track keys: %s<br>" % station_tracks_keys

    playlists = rdio.call('getUserPlaylists', { :user => user_key, :kind => "owned" })['result']
    response += "Found playlists:<br>"
    playlists.each do |playlist|
      response += "%s<br>" % playlist["name"]
      if playlist["name"] == station_name
        status = rdio.call('deletePlaylist', { :playlist => playlist["key"] })["status"]
        if status == "ok"
          response += "Playlist %s deleted<br>" % playlist["name"]
        end
      end
    end
    new_playlist_name = station_name unless new_playlist_name
    new_playlist = rdio.call('createPlaylist', { :name => new_playlist_name, :description => "Playlist based on %s, built with rdios2p.heroku.com" % station_name, :tracks => station_tracks_keys, :isPublished => "false" })
    new_playlist_status = new_playlist['status']
    new_playlist_key = new_playlist['result']['key']
    new_playlist_sync_status = rdio.call('addToSynced', { :keys => new_playlist_key })['status']
    if new_playlist_status == "ok"
      response += "New playlist key: %s<br>" % new_playlist_key
    end
    if new_playlist_sync_status == "ok"
      response += "Playlist marked for syncing<br>"
    end
    response += '</body></html>'
    return response
  else
    redirect to('/')
  end
end

get '/test' do
  access_token = session[:at]
  access_token_secret = session[:ats]
  if access_token and access_token_secret
    rdio = Rdio.new([RDIO_CONSUMER_KEY, RDIO_CONSUMER_SECRET],
    [access_token, access_token_secret])
    response = "<html><body><br>"
    response += "params: %s<br>" % params
    user_key  = rdio.call('currentUser')['result']['key']
    station = rdio.call('getObjectFromUrl', { :url => 'http://www.rdio.com/stations/people/rdiocurated/playlists/10909198/Today%27s_EDM_Hits/'})['result']
    station_key = station["key"]
    station_name = station["name"]
    response += "Station name: %s<br>" % station_name
    station_tracks = rdio.call('generateStation', { :station_key => station_key, :count => "100" })
    response += "%s" % station_tracks
  else
    redirect to('/login')
  end
end

get '/login' do
  session.clear
  # begin the authentication process
  rdio = Rdio.new([RDIO_CONSUMER_KEY, RDIO_CONSUMER_SECRET])
  callback_url = (URI.join request.url, '/callback').to_s
  url = rdio.begin_authentication(callback_url)
  # save our request token in the session
  session[:rt] = rdio.token[0]
  session[:rts] = rdio.token[1]
  # go to Rdio to authenticate the app
  redirect url
end

get '/callback' do
  # get the state from cookies and the query string
  request_token = session[:rt]
  request_token_secret = session[:rts]
  verifier = params[:oauth_verifier]
  # make sure we have everything we need
  if request_token and request_token_secret and verifier
    # exchange the verifier and request token for an access token
    rdio = Rdio.new([RDIO_CONSUMER_KEY, RDIO_CONSUMER_SECRET],
    [request_token, request_token_secret])
    rdio.complete_authentication(verifier)
    # save the access token in cookies (and discard the request token)
    session[:at] = rdio.token[0]
    session[:ats] = rdio.token[1]
    session.delete(:rt)
    session.delete(:rts)
    # go to the home page
    redirect to('/')
  else
    # we're missing something important
    redirect to('/logout')
  end
end

get '/logout' do
  session.clear
  redirect to('/')
end
