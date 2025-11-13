
#### Główny kod aplikacji app.py ####

from flask import Flask, render_template, request, redirect, url_for, session
import pandas as pd
import os
from datetime import datetime
import requests
from requests.adapters import HTTPAdapter
from urllib3 import PoolManager
import ssl

app = Flask(__name__)
app.secret_key = "tajny_klucz"  # zmień na swój własny klucz

# Lista kodów województw CEPiK (01–16)
WOJEWODZTWA = [f"{i:02}" for i in range(1, 17)]

@app.route("/", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        username = request.form.get("username")
        password = request.form.get("password")

        if username == "admin" and password == "admin123":
            session["user"] = username
            return redirect(url_for("form"))
        else:
            return render_template("login.html", error="Niepoprawne dane logowania")
    return render_template("login.html")

@app.route("/form", methods=["GET", "POST"])
def form():
    if "user" not in session:
        return redirect(url_for("login"))

    if request.method == "POST":
        year = request.form.get("year")
        if not year.isdigit() or len(year) != 4:
            return render_template("form.html", error="Podaj poprawny rok (np. 2022).")

        result = download_cepik_data(int(year))
        return render_template("result.html", year=year, result=result)

    return render_template("form.html")

class SSLAdapter(HTTPAdapter):
    """Adapter do obniżenia poziomu bezpieczeństwa SSL (omija DH_KEY_TOO_SMALL)"""
    def init_poolmanager(self, *args, **kwargs):
        context = ssl.create_default_context()
        context.set_ciphers('DEFAULT:@SECLEVEL=1')  # obniża wymóg DH
        kwargs['ssl_context'] = context
        return super().init_poolmanager(*args, **kwargs)

def download_cepik_data(year: int):
    base_url = "https://api.cepik.gov.pl/pojazdy"
    results = []

    session_req = requests.Session()
    session_req.mount('https://', SSLAdapter())  # używamy naszego SSLAdaptera

    for woj in WOJEWODZTWA:
        folder = os.path.join("data", woj)
        os.makedirs(folder, exist_ok=True)

        for month in range(1, 13):
            start_date = f"{year}{month:02}01"
            end_date = f"{year}{month:02}{days_in_month(year, month):02}"

            params = {
                "wojewodztwo": woj,
                "data-od": start_date,
                "data-do": end_date,
                "typ-daty": 2,
                "tylko-zarejestrowane": "true",
                "pokaz-wszystkie-pola": "true",
                "limit": 500
            }

            print(f"Pobieranie: {woj} - {year}-{month:02}")
            try:
                response = session_req.get(base_url, params=params, timeout=30)
                print(f"Status code: {response.status_code}")
                response.raise_for_status()
                data = response.json()

                if "data" in data and data["data"]:
                    df = pd.json_normalize(data["data"])
                    file_path = os.path.join(folder, f"{year}_{month:02}.csv")
                    df.to_csv(file_path, index=False)
                    results.append(f"Zapisano: {file_path}")
                else:
                    results.append(f"Brak danych dla {woj} - {year}-{month:02}")

            except Exception as e:
                results.append(f"Błąd dla {woj} - {year}-{month:02}: {e}")

    return results

def days_in_month(year, month):
    if month in [1, 3, 5, 7, 8, 10, 12]:
        return 31
    elif month == 2:
        return 29 if (year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)) else 28
    else:
        return 30

@app.route("/logout")
def logout():
    session.pop("user", None)
    return redirect(url_for("login"))

#### form html ####
<!DOCTYPE html>
<html lang="pl">
<head>
  <meta charset="UTF-8">
  <title>Formularz CEPiK</title>
</head>
<body>
  <h2>Pobieranie danych CEPiK</h2>
  <form method="POST">
    <label>Podaj rok:</label><br>
    <input type="text" name="year" required><br><br>
    <input type="submit" value="Pobierz dane">
  </form>
  {% if error %}
    <p style="color:red;">{{ error }}</p>
  {% endif %}
  <p><a href="{{ url_for('logout') }}">Wyloguj</a></p>
</body>
</html>

#### login.html ####
<!DOCTYPE html>
<html lang="pl">
<head>
  <meta charset="UTF-8">
  <title>Logowanie</title>
</head>
<body>
  <h2>Logowanie do systemu CEPiK</h2>
  <form method="POST">
    <label>Użytkownik:</label><br>
    <input type="text" name="username" required><br><br>
    <label>Hasło:</label><br>
    <input type="password" name="password" required><br><br>
    <input type="submit" value="Zaloguj">
  </form>
  {% if error %}
    <p style="color:red;">{{ error }}</p>
  {% endif %}
</body>
</html>

#### result.html ####
<!DOCTYPE html>
<html lang="pl">
<head>
  <meta charset="UTF-8">
  <title>Wyniki CEPiK</title>
</head>
<body>
  <h2>Wyniki pobierania danych dla roku {{ year }}</h2>
  <ul>
    {% for item in result %}
      <li>{{ item }}</li>
    {% endfor %}
  </ul>
  <a href="{{ url_for('form') }}">Powrót</a> |
  <a href="{{ url_for('logout') }}">Wyloguj</a>
</body>
</html>


if __name__ == "__main__":
    app.run(debug=True)
