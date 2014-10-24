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

$stdout.sync = true

enable :sessions
disable :protection

set :public_folder, File.dirname(__FILE__) + '/static'

get '/' do
  access_token = session[:at]
  access_token_secret = session[:ats]
  if access_token and access_token_secret
    response = '<html><body><title>Rdio Station to Playlist</title>
    <p><h1>RdioS2P</h1></p>
    <p>Tracks from the specified station will be added to a playlist on your Rdio account.<br>
    If no playlist is specified, it will have the same name as the station.<br>
    If you prefer, the playlist can be deleted entirely and recreated with all new tracks.<br>
    If a track already exists in the playlist, it will not be added.<br>
    The code for this app is available <a href="https://github.com/hjbotha/rdios2p">here</a> under the MIT licence.
    </p>

    <form method="get" enctype="text/plain" action="/CreateStation">
    <hidden name="version" value="2">
    <table border=0>
    <tr><td>Station URL:</td><td><input type="text" name="station_url"></td></tr>
    <tr><td>Playlist Name:</td><td><input type="text" name="playlist_name"> (optional, defaults to the name of the station)</td></tr>
    <tr><td colspan=2>If playlist already exists:</td></tr>
    <tr><td colspan=2><input type="radio" name="existing" value="addto" checked>Add tracks</td></tr>
    <tr><td colspan=2><input type="radio" name="existing" value="delete">Delete and replace</td></tr>
    <tr><td colspan=2><input type="submit"></td></tr></form>'
    return response
  else
    redirect to('/login')
  end
end

get '/CreateStation' do
  access_token = session[:at]
  access_token_secret = session[:ats]
  if access_token and access_token_secret and params[:station_url] and params[:existing] and params[:version] == 2
    rdio = Rdio.new([RDIO_CONSUMER_KEY, RDIO_CONSUMER_SECRET], [access_token, access_token_secret])
    response = "<html><body><title>Rdio Station to Playlist</title><p><h1>RdioS2P</h1></p>"
response += "<p>Getting your information..."
    user_key  = rdio.call('currentUser')['result']['key']
response += " Done.<br>"
response += "Getting station key..."
    station = rdio.call('getObjectFromUrl', { :url => params[:station_url] })['result']
response += " Done.<br>"
    station_key = station["key"]
    station_name = station["name"]
    if params[:playlist_name] and params[:playlist_name] != "" then
      playlist_name = params[:playlist_name]
    else
      playlist_name = station_name
    end

    response += "Getting track list..."
    station_tracks = rdio.call('generateStation', { :station_key => station_key, :count => "100" })['result']["tracks"]
    response += " Done.<br>"
    station_tracks_keys_array = []
    station_tracks.each do |track|
      station_tracks_keys_array << track["key"]
    end
    station_tracks_keys = station_tracks_keys_array * ","
    playlist_key = "undefined"
    response += "Getting a list of your playlists..."
    playlists = rdio.call('getUserPlaylists', { :user => user_key, :kind => "owned" })['result']
    response += " Done.<br>"
    playlists.each do |playlist|
      if playlist["name"] == playlist_name
        if params[:existing] == "delete"
          response += "Deleting the old playlist..."
          delete_playlist = rdio.call('deletePlaylist', { :playlist => playlist["key"] })
          response += " Done.<br>"
          break
        else
          playlist_key = playlist["key"]
          break
        end
      end
    end
    if playlist_key == "undefined" then # Playlist with the specified name doesn't exist, so create one
      response += "Creating new playlist and marking for download..."
      playlist = rdio.call('createPlaylist', { :name => playlist_name, :description => "Playlist built with rdios2p.heroku.com", :tracks => station_tracks_keys, :isPublished => "false" })['result']
      playlist_key = playlist['key']
      playlist_sync_status = rdio.call('addToSynced', { :keys => playlist_key })['status']
      response += " Done.<br>"
    else # Playlist does exist, so get tracks that don't already exist in playlist and add them
      playlist_tracks_keys_array = []
      response += "Getting details about the playlist..."
      playlist = rdio.call('get', { :keys => playlist_key, :extras => "tracks" })['result'][playlist_key]
      response += " Done.<br>"
      playlist['tracks'].each do |track|
        playlist_tracks_keys_array << track["key"]
      end
      new_tracks_keys_array = station_tracks_keys_array - playlist_tracks_keys_array
      new_tracks_keys = new_tracks_keys_array * ","
      response += "Adding new tracks to playlist..."
      add_to_playlist = rdio.call('addToPlaylist', { :playlist => playlist["key"], :tracks => new_tracks_keys })
      response += " Done.<br>"
    end
    response += "All done.<br>"
    response += "</p><p>"
    response += "Click <a href=\"%s\">here</a> to go to the playlist.<br>" % playlist['shortUrl']
    response += "</p><p>"
    response += "Wouldn't it have been cool if all that was being displayed as it was happening?<br>
    Sadly I don't know how to do that. If you do, look at <a href=\"https://github.com/hjbotha/rdios2p\">the code</a> and let me know!"
    response += "</p>"
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
    rdio = Rdio.new([RDIO_CONSUMER_KEY, RDIO_CONSUMER_SECRET], [access_token, access_token_secret])

    result = rdio.call('generateStation', { :station_key => "gr504", :count => "100" })['result']

    response = '%s' % result
    return response
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
